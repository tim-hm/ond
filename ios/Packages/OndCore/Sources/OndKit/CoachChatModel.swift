import Foundation
import Observation
import os

/// One conversation with the coach: the transcript and the reply streaming
/// into it.
///
/// `ExplanationModel`'s accumulate-and-republish pattern applied to a
/// transcript, with a ``RevealPacer`` between the two halves: chunks arrive at
/// the model's own cadence and the transcript republishes on a regular twelve a
/// second, so the paragraph fills in at a rate a person can follow rather than
/// at whatever rhythm the provider happened to have. The transcript is seeded
/// from a persisted ``Conversation`` and written back at each terminal point —
/// after the person's turn, when a reply finishes or fails, and on cancel —
/// never per chunk, because the store rewrites its whole file per save and a
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

    /// How often a streaming reply republishes, for a view that wants to animate
    /// one step over exactly the window it will be on screen for. The pacer has
    /// the why; this is the part of it the transcript's reader needs to know.
    public static let revealTick = RevealPacer.tick

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

    /// Whether a reply is still arriving on screen. The view disables send —
    /// not the composer — while it is: typing the next question over a
    /// streaming answer is fine, interleaving two answers is not.
    ///
    /// True until the *reveal* drains, not merely until the stream ends: the
    /// last second of an answer is still being written, and it is also the
    /// window the transcript is still growing in, which is what the scroll
    /// reads this for.
    public private(set) var isReplying = false

    /// Where the newest reply came from, or nil before the first one. Cleared
    /// when a send starts, so a stale verdict never outlives the question it
    /// answered.
    public private(set) var lastReplySource: GuidanceSource?

    /// The reply in flight, or nil between replies. One value rather than four
    /// vars, so the half writing into the buffer and the half publishing out of
    /// it cannot disagree about which reply they are on.
    private struct Reply {
        /// Fixed before the first chunk, so the row grows rather than being
        /// replaced.
        let id = UUID()
        var pacer = RevealPacer()

        /// Withheld until the prose has finished revealing: a card above half an
        /// answer proposes something the reply has not yet justified.
        var proposal: CoachProposal?
    }

    private let assistant: any AssistantReading
    private let store: any ConversationStoring
    private let clock: any SessionClock
    private var conversation: Conversation
    private var reply: Reply?
    private var reader: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?

    public convenience init(
        conversation: Conversation,
        store: any ConversationStoring,
        assistant: any AssistantReading
    ) {
        self.init(
            conversation: conversation,
            store: store,
            assistant: assistant,
            clock: SystemClock()
        )
    }

    /// `SessionModel`'s bargain, for `SessionClock`'s reason: outside a test
    /// there is one clock a reveal can be paced against, so the public
    /// initialiser does not offer the choice.
    init(
        conversation: Conversation,
        store: any ConversationStoring,
        assistant: any AssistantReading,
        clock: any SessionClock
    ) {
        self.conversation = conversation
        self.store = store
        self.assistant = assistant
        self.clock = clock
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
        reply = Reply()

        // Opened before the task rather than inside it, so the request is in
        // flight the moment send returns and nothing observable races the
        // caller.
        let chunks = assistant.chat(history: history, message: message)

        reader = Task {
            // The reveal starts alongside the read rather than after it, so the
            // first words are on screen a tick after they arrive rather than a
            // tick after the stream ends. Both halves are main-actor isolated,
            // so they interleave at their own suspension points and neither
            // needs a lock over the buffer between them.
            async let revealed: Void = reveal()
            await read(chunks)
            reply?.pacer.close()
            await revealed

            // Cancellation is the screen going away: `cancel` has already
            // flushed and persisted, and nobody is left to read a quiet
            // sentence either.
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// Pours one reply into the pacer's buffer, chunk by chunk.
    ///
    /// Puts nothing on screen itself — [`reveal`] does that, at its own rate —
    /// so a broken stream needs no handling here beyond a line in the log: the
    /// drain that follows publishes whatever arrived, and [`finish`] answers for
    /// a reply that never said anything, whether it broke or ended cleanly.
    private func read(_ chunks: AsyncThrowingStream<AssistantChunk, Error>) async {
        do {
            for try await chunk in chunks where !chunk.text.isEmpty || chunk.proposal != nil {
                // The contract is at most one proposal per reply; a second is
                // dropped here so a misbehaving stream cannot swap the card out
                // from under a tap.
                if reply?.proposal == nil, let arrived = chunk.proposal {
                    reply?.proposal = arrived
                }

                // The source is constant across a reply's chunks, and `send`
                // cleared it, so the first chunk to arrive is the whole answer.
                if lastReplySource == nil {
                    lastReplySource = chunk.source
                }

                reply?.pacer.append(chunk.text)
            }
        } catch {
            // Cancellation is the screen going away, not a failure.
            if !(error is CancellationError) {
                Self.logger.notice(
                    "the reply stopped early: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Publishes the reply a little at a time until the stream has closed and
    /// the buffer is empty.
    private func reveal() async {
        while reply?.pacer.isSettled == false {
            reply?.pacer.release()
            publish()

            // Checked again after publishing rather than only at the top, so a
            // reply that has just landed whole is not held behind one last tick
            // of nothing before its turn ends.
            guard reply?.pacer.isSettled == false else { return }
            guard await (try? clock.sleep(until: clock.now.advanced(by: RevealPacer.tick))) != nil
            else { return }
        }
    }

    /// Writes what has been revealed into the reply's row, appending it on the
    /// first words rather than reserving one.
    ///
    /// Nothing is drawn for a reply that has arrived but not yet been released:
    /// an empty bubble reads as a lost message, which is the same reason an
    /// offer-only reply draws no bubble either.
    private func publish() {
        guard let reply else { return }

        let proposal = reply.pacer.isSettled ? reply.proposal : nil
        guard !reply.pacer.revealed.isEmpty || proposal != nil else { return }

        let turn = ChatTurn(
            id: reply.id,
            role: .coach,
            text: reply.pacer.revealed,
            proposal: proposal
        )
        if transcript.last?.id == reply.id {
            transcript[transcript.count - 1] = turn
        } else {
            transcript.append(turn)
        }
    }

    /// The reply's terminal point, whether the stream ended, broke, or said
    /// nothing at all.
    ///
    /// One place rather than the two the empty-reply check used to be written
    /// in: a stream that ended cleanly having said nothing and one that died
    /// before its first chunk are the same failure from where the person sits —
    /// they watched their message send and got back nothing. On the reply row's
    /// absence rather than on the text, because a reply that was only ever its
    /// offer still answered, and an apology under a live card would contradict
    /// it.
    private func finish() {
        if let reply, transcript.last?.id != reply.id {
            transcript.append(ChatTurn(role: .coach, text: Self.unavailableReply))
        }
        reply = nil
        isReplying = false
        persist()
    }

    /// Stops the stream. Called when the view goes away, so no request
    /// outlives the screen — and persists, because the partial text the screen
    /// kept is worth exactly as much on the next open as it was mid-stream.
    public func cancel() {
        reader?.cancel()
        reader = nil

        // Everything at once, before the save. The pace is for somebody
        // watching and by here nobody is, so what the store keeps should be
        // what the server said: a conversation that reopened *shorter* than the
        // answer that arrived would be this screen losing text it already held.
        reply?.pacer.flush()
        publish()
        reply = nil
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
