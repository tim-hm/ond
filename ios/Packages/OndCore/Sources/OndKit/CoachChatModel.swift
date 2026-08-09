import Foundation
import Observation
import os

/// One conversation with the coach: the transcript, the reply streaming into
/// it, and the voice reading that reply aloud.
///
/// `ExplanationModel`'s accumulate-and-republish pattern applied to a
/// transcript: the growing reply is republished on every chunk, so the
/// paragraph fills in as it is written. The transcript is seeded from a
/// persisted ``Conversation`` and written back at each terminal point — after
/// the person's turn, when a reply finishes or fails, and on cancel — never
/// per chunk, because the store rewrites its whole file per save and a
/// streaming reply would rewrite it per token. The one loss window is a hard
/// app kill mid-stream, which loses the partial reply and nothing else.
///
/// Failure is one quiet sentence in the transcript, never an error state: the
/// composer stays alive, nothing retries on its own, and a reply that broke
/// mid-answer keeps what arrived — half an answer is still worth reading.
@MainActor
@Observable
public final class CoachChatModel {
    /// What the transcript says when a reply never started. In the coach's
    /// row, not a banner: the conversation is the screen, so the conversation
    /// is where the answer — including this one — appears.
    static let unavailableReply =
        "The coach can't answer just now — nothing else is affected, so try again in a little while."

    private static let logger = Logger(category: "assistant")

    /// The conversation so far, oldest first. The last turn grows in place
    /// while a reply streams.
    public private(set) var transcript: [ChatTurn]

    /// Whether a reply is currently streaming. The view disables send — not
    /// the composer — while it is: typing the next question over a streaming
    /// answer is fine, interleaving two answers is not.
    public private(set) var isReplying = false

    /// Where the newest reply came from, or nil before the first one. Cleared
    /// when a send starts, so a stale verdict never outlives the question it
    /// answered.
    public private(set) var lastReplySource: GuidanceSource?

    /// The speak-back toggle. Turning it off silences the voice immediately;
    /// turning it on applies from the next reply, so the voice never starts
    /// mid-paragraph on text the person has already read.
    public var isSpeakingAloud = false {
        didSet {
            if !isSpeakingAloud {
                voice.stop()
            }
        }
    }

    private let assistant: any AssistantReading
    private let voice: any CoachVoice
    private let store: any ConversationStoring
    private var conversation: Conversation
    private var reader: Task<Void, Never>?
    private var sentences = SentenceBuffer()

    public init(
        conversation: Conversation,
        store: any ConversationStoring,
        assistant: any AssistantReading,
        voice: any CoachVoice
    ) {
        self.conversation = conversation
        self.store = store
        self.assistant = assistant
        self.voice = voice
        transcript = conversation.turns
    }

    /// Sends one message and starts streaming the reply.
    ///
    /// Ignored while a reply is streaming — the send affordance is disabled
    /// then, and a race through it would interleave two answers. Stops the
    /// voice first: a new question makes the old answer's remainder noise.
    public func send(_ message: String) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isReplying else { return }

        voice.stop()
        // Only what the server will read: it silently keeps the newest
        // `maxHistoryDepth` turns, so a longer upload is bytes it provably
        // throws away. Each turn's text is clamped to the message bound too —
        // a coach reply regularly runs past it, the server refuses an
        // over-long history turn outright, and a persisted transcript would
        // replay that refusal forever.
        let history = transcript.suffix(ChatTurn.maxHistoryDepth).map { turn in
            ChatTurn(
                id: turn.id,
                role: turn.role,
                text: String(turn.text.prefix(ChatTurn.maxMessageLength)),
                offer: turn.offer
            )
        }
        transcript.append(ChatTurn(role: .person, text: message))
        persist()
        isReplying = true
        lastReplySource = nil
        sentences = SentenceBuffer()

        // Opened before the task rather than inside it, so the request is in
        // flight the moment send returns and nothing observable races the
        // caller.
        let chunks = assistant.chat(history: history, message: message)

        reader = Task {
            await read(chunks)
            isReplying = false
            persist()
        }
    }

    /// Streams one reply into the transcript, chunk by chunk.
    private func read(_ chunks: AsyncThrowingStream<AssistantChunk, Error>) async {
        // One identity for the whole reply, fixed before the first chunk,
        // so the row grows rather than being replaced.
        let replyId = UUID()
        var accumulated = ""
        var offer: ExerciseOffer?

        do {
            for try await chunk in chunks where !chunk.text.isEmpty || chunk.offer != nil {
                // The contract is at most one offer per reply; a second is
                // dropped here so a misbehaving stream cannot swap the
                // card out from under a tap.
                if offer == nil, let arrived = chunk.offer {
                    offer = arrived
                }

                let grown = ChatTurn(
                    id: replyId,
                    role: .coach,
                    text: accumulated + chunk.text,
                    offer: offer
                )
                if accumulated.isEmpty, transcript.last?.id != replyId {
                    // The source is constant across a reply's chunks, so
                    // the first is the whole answer.
                    lastReplySource = chunk.source
                    transcript.append(grown)
                } else {
                    transcript[transcript.count - 1] = grown
                }
                accumulated = grown.text

                speak(sentences.append(chunk.text))
            }

            if let rest = sentences.flush() {
                speak([rest])
            }
        } catch {
            // Cancellation is the screen going away, not a failure — and
            // nobody is left to read a quiet sentence either.
            if !(error is CancellationError) {
                Self.logger.notice(
                    "the reply stopped early: \(error.localizedDescription, privacy: .public)"
                )
                if accumulated.isEmpty {
                    transcript.append(ChatTurn(role: .coach, text: Self.unavailableReply))
                }
            }
        }
    }

    /// Stops the stream and the voice. Called when the view goes away, so
    /// neither a request nor a monologue outlives the screen — and persists,
    /// because the partial text the screen kept is worth exactly as much on
    /// the next open as it was mid-stream.
    public func cancel() {
        reader?.cancel()
        reader = nil
        voice.stop()
        isReplying = false
        persist()
    }

    /// Silences the voice without touching the speak-back preference — for
    /// the moment an offered session starts and owns the audio.
    public func stopSpeaking() {
        voice.stop()
    }

    /// Copies the transcript into the conversation and hands it to the store.
    ///
    /// The store's actor serialises the writes and its upsert is idempotent,
    /// so the cancel-then-task-end double save is harmless; a conversation
    /// with no turns is refused there, so an untouched chat never hits disk.
    private func persist() {
        conversation.turns = transcript
        conversation.updatedAt = .now
        let snapshot = conversation
        Task { [store] in
            await store.save(snapshot)
        }
    }

    private func speak(_ completed: [String]) {
        guard isSpeakingAloud else { return }
        for sentence in completed {
            voice.speak(sentence)
        }
    }
}

/// Accumulates streamed text and releases it a sentence at a time, so the
/// voice can start on the first sentence while the rest of the reply is still
/// being written.
///
/// A boundary is a sentence terminator (`.` `!` `?` `…`) followed by
/// whitespace, or a newline. Requiring the whitespace is what keeps a decimal
/// ("a 4.7 rhythm") or a mid-number chunk split from ending a sentence early;
/// the cost is that the final sentence of a reply never sees trailing
/// whitespace, which is what [`flush()`](SentenceBuffer.flush) is for.
struct SentenceBuffer {
    private var pending = ""

    /// Adds streamed text and returns the sentences it completed, in order,
    /// trimmed. Chunk boundaries carry no meaning, so a sentence can complete
    /// mid-chunk or span several.
    mutating func append(_ text: String) -> [String] {
        pending += text

        var completed: [String] = []
        while let boundary = firstBoundary() {
            let sentence = String(pending[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pending.removeSubrange(..<boundary)
            if !sentence.isEmpty {
                completed.append(sentence)
            }
        }
        return completed
    }

    /// The unterminated remainder, trimmed, or nil. Called when the stream
    /// ends: a reply's last sentence is complete by virtue of the stream
    /// ending, whether or not its punctuation ever arrived.
    mutating func flush() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return rest.isEmpty ? nil : rest
    }

    /// The index just past the first sentence boundary, or nil while every
    /// sentence is still open.
    private func firstBoundary() -> String.Index? {
        var index = pending.startIndex
        while index < pending.endIndex {
            let character = pending[index]
            let next = pending.index(after: index)

            if character.isNewline {
                return next
            }
            if ".!?…".contains(character), next < pending.endIndex, pending[next].isWhitespace {
                return next
            }
            index = next
        }
        return nil
    }
}
