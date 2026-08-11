import Foundation
@testable import OndKit
import Testing

/// The pacing as the transcript sees it, on a clock the test moves — so every
/// assertion reads an exact number of ticks rather than whatever the scheduler
/// happened to deliver. `RevealPacerTests` covers the arithmetic; this covers
/// what the screen and the store are left holding.
@Suite("Coach chat reveal")
@MainActor
struct CoachChatRevealTests {
    private func pacedModel(_ script: ChatScript, clock: ManualClock) -> CoachChatModel {
        CoachChatModel(
            conversation: Conversation(),
            store: InMemoryConversationStore(),
            assistant: script.assistant,
            clock: clock
        )
    }

    /// Advances the reveal a tick at a time until `condition` holds.
    ///
    /// Driven by the condition rather than by a tick count, because a count
    /// races the loop it is meant to drive: an advance that lands before the
    /// revealer has computed its deadline is one the revealer never sees, and
    /// the reveal then waits for a tick the test has already spent. `Settle`'s
    /// rule applies to the condition — wait on something weaker than the
    /// assertion.
    private func drain(_ clock: ManualClock, until condition: () -> Bool) async throws {
        for _ in 0 ..< 400 where !condition() {
            clock.advance(by: CoachChatModel.revealTick)
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// The core contract the scroll depends on: the answer is still arriving on
    /// screen after the stream has ended, so the flag that says "still growing"
    /// must outlive the stream rather than the transport.
    @Test("A reply is still replying after the stream ends, until the reveal drains")
    func replyingOutlivesTheStream() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        let whole = "A longer exhale lengthens the parasympathetic phase and settles you."
        model.send("What settles me?")
        try await settle(until: { model.isReplying })

        script.yield(AssistantChunk(text: whole, source: .model))
        script.finish()

        try await drain(clock, until: { model.transcript.count == 2 })
        let shown = try #require(model.transcript.last?.text)
        #expect(!shown.isEmpty, "the first words are on screen a tick after they arrive")
        #expect(shown.count < whole.count, "and only the first words")
        #expect(model.isReplying, "the stream is over; the answer is not")

        try await drain(clock, until: { !model.isReplying })
        #expect(model.transcript.last?.text == whole)
        #expect(!model.isReplying)
    }

    /// Cancel is the screen going away, so nobody is watching the pace — and
    /// what the store keeps must be what the server said. A conversation that
    /// reopened shorter than the answer that arrived would be the screen losing
    /// text it already held.
    @Test("Cancel keeps everything that arrived, not just what was shown")
    func cancelKeepsWhatArrivedRatherThanWhatWasShown() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        let whole = "The first part, the second part, and a third part after that."
        model.send("hello")
        try await settle(until: { model.isReplying })
        script.yield(AssistantChunk(text: whole, source: .model))

        try await drain(clock, until: { model.transcript.count == 2 })
        #expect(try #require(model.transcript.last?.text).count < whole.count)

        model.cancel()
        #expect(model.transcript.last?.text == whole)
        #expect(!model.isReplying)
    }

    /// The card appears with the finished answer, never above half of one: an
    /// offer under a paragraph still being written proposes a session the reply
    /// has not yet justified.
    @Test("The offer waits for the prose to finish revealing")
    func theOfferWaitsForTheProse() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        model.send("what should I do now?")
        try await settle(until: { model.isReplying })
        script.yield(AssistantChunk(
            text: "Box breathing would steady you before that meeting.",
            source: .model,
            offer: ExerciseOffer(techniqueSlug: "box-breathing")
        ))
        script.finish()

        try await drain(clock, until: { model.transcript.count == 2 })
        #expect(model.transcript.last?.offer == nil, "no card above a half-written answer")

        try await drain(clock, until: { !model.isReplying })
        #expect(model.transcript.last?.offer?.techniqueSlug == "box-breathing")
        #expect(!model.isReplying)
    }

    /// A breath-hold offer travels the same path as an exercise one and waits
    /// on the same prose, so the second kind of card needed no second rule —
    /// which is the whole point of the transcript holding one proposal rather
    /// than a field per kind.
    @Test("A breath-hold proposal rides the reply on the exercise offer's terms")
    func aBoltProposalRidesTheReply() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        model.send("how am I doing?")
        try await settle(until: { model.isReplying })
        script.yield(AssistantChunk(
            text: "A breath-hold score would tell us where to pitch this.",
            source: .model,
            proposal: .boltTest
        ))
        script.finish()

        try await drain(clock, until: { model.transcript.count == 2 })
        #expect(model.transcript.last?.proposal == nil, "no card above a half-written answer")

        try await drain(clock, until: { !model.isReplying })
        #expect(model.transcript.last?.proposal == .boltTest)
        #expect(
            model.transcript.last?.offer == nil,
            "and it is not mistaken for an exercise offer"
        )
    }

    /// A stream that ends cleanly having said nothing is a failure wearing
    /// success's status. The check runs after the drain now, so it has to
    /// survive a reveal that never had anything to reveal.
    @Test("A stream that says nothing still leaves the quiet sentence")
    func anEmptyStreamStillApologises() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        model.send("hello")
        try await settle(until: { model.isReplying })
        script.finish()

        // A tick even for a reply with nothing in it: the revealer is asleep
        // when the stream closes, and it is waking that finds the buffer empty
        // and ends the turn.
        try await drain(clock, until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript.last?.text == CoachChatModel.unavailableReply)
    }

    /// Cancelling before anything arrived leaves the question standing alone.
    /// An apology addressed to somebody who has left the screen is a sentence
    /// they come back to and have to make sense of.
    @Test("A cancel before anything arrived adds no apology")
    func aCancelBeforeAnythingArrivedIsSilent() async throws {
        let clock = ManualClock()
        let script = ChatScript()
        let model = pacedModel(script, clock: clock)

        model.send("hello")
        try await settle(until: { model.isReplying })
        model.cancel()
        try await Task.sleep(for: .milliseconds(30))

        #expect(model.transcript.count == 1)
        #expect(model.transcript[0].role == .person)
        #expect(!model.isReplying)
    }
}
