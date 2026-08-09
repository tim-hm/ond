import Foundation
import Observation
import os

/// One conversation with the coach: the transcript and the reply streaming
/// into it.
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

    /// The conversation's title as of the current transcript, or nil before
    /// the first question. Derived live — the screen it names is the one
    /// place a conversation gains its first question while being watched.
    public var title: String? {
        Conversation.title(of: transcript)
    }

    /// Whether a reply is currently streaming. The view disables send — not
    /// the composer — while it is: typing the next question over a streaming
    /// answer is fine, interleaving two answers is not.
    public private(set) var isReplying = false

    /// Where the newest reply came from, or nil before the first one. Cleared
    /// when a send starts, so a stale verdict never outlives the question it
    /// answered.
    public private(set) var lastReplySource: GuidanceSource?

    private let assistant: any AssistantReading
    private let store: any ConversationStoring
    private var conversation: Conversation
    private var reader: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?

    public init(
        conversation: Conversation,
        store: any ConversationStoring,
        assistant: any AssistantReading
    ) {
        self.conversation = conversation
        self.store = store
        self.assistant = assistant
        transcript = conversation.turns
    }

    /// Sends one message and starts streaming the reply.
    ///
    /// Ignored while a reply is streaming — the send affordance is disabled
    /// then, and a race through it would interleave two answers.
    public func send(_ message: String) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isReplying else { return }

        // Only what the server will read: it silently keeps the newest
        // `maxHistoryDepth` turns, so a longer upload is bytes it provably
        // throws away. The per-turn length bound is the repository's business,
        // enforced where the wire message is built.
        let history = Array(transcript.suffix(ChatTurn.maxHistoryDepth))
        transcript.append(ChatTurn(role: .person, text: message))
        persist()
        isReplying = true
        lastReplySource = nil

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
            }

            // A stream that ends cleanly having said nothing — every chunk
            // dropped, or none sent — is a failure wearing success's status:
            // the person watched their message send and got literally nothing
            // back. The reply-turn check rather than `accumulated`, because a
            // reply that was only ever an offer still answered.
            if transcript.last?.id != replyId {
                transcript.append(ChatTurn(role: .coach, text: Self.unavailableReply))
            }
        } catch {
            // Cancellation is the screen going away, not a failure — and
            // nobody is left to read a quiet sentence either.
            if !(error is CancellationError) {
                Self.logger.notice(
                    "the reply stopped early: \(error.localizedDescription, privacy: .public)"
                )
                // On the reply turn's absence, not `accumulated`: a reply
                // that led with its offer has already answered in part, and
                // an apology under a live card would contradict it.
                if transcript.last?.id != replyId {
                    transcript.append(ChatTurn(role: .coach, text: Self.unavailableReply))
                }
            }
        }
    }

    /// Stops the stream. Called when the view goes away, so no request
    /// outlives the screen — and persists, because the partial text the screen
    /// kept is worth exactly as much on the next open as it was mid-stream.
    public func cancel() {
        reader?.cancel()
        reader = nil
        isReplying = false
        persist()
    }

    /// Copies the transcript into the conversation and hands it to the store.
    ///
    /// A no-op while nothing changed, which is what keeps reading cheap and
    /// honest: dismissing a chat that was only read neither rewrites the
    /// store's file nor bumps the conversation's recency in the list, and the
    /// cancel-then-task-end double call after an interrupted reply costs one
    /// write, not two. A conversation with no turns is refused by the store,
    /// so an untouched chat never hits disk.
    ///
    /// Saves are chained, each awaiting its predecessor, because independent
    /// `Task`s carry no ordering: the send's question-only snapshot landing
    /// *after* the finish's full-reply snapshot would leave the reply off
    /// disk — and the equality guard, comparing against the eagerly updated
    /// copy, would then never re-save it.
    private func persist() {
        guard transcript != conversation.turns else { return }
        conversation.turns = transcript
        conversation.updatedAt = .now
        let snapshot = conversation
        let previous = pendingSave
        pendingSave = Task { [store] in
            await previous?.value
            await store.save(snapshot)
        }
    }
}
