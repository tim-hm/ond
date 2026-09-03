import Foundation
@testable import OndKit
import Testing

@Suite("Coach chat")
@MainActor
struct CoachChatTests {
    /// The transcript is readable between chunks — the person's turn lands
    /// immediately, the coach's row appears with the first chunk and grows in
    /// place, keeping one identity so the view animates a paragraph filling
    /// in rather than replacing rows.
    @Test("The reply grows in place while streaming")
    func replyAccumulatesAcrossChunks() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("What helps with sleep?")
        try await settle(until: { model.isReplying })

        #expect(model.transcript.count == 1, "the person's turn lands before any reply")
        #expect(model.transcript[0].role == .person)
        #expect(model.isReplying)

        script.yield(AssistantChunk(text: "A longer exhale ", source: .model))
        try await settle(until: { model.transcript.count == 2 })
        let replyId = model.transcript[1].id

        script.yield(AssistantChunk(text: "settles you.", source: .model))
        script.finish()
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript[1].role == .coach)
        #expect(model.transcript[1].text == "A longer exhale settles you.")
        #expect(model.transcript[1].id == replyId, "the reply keeps one identity as it grows")
        #expect(!model.isReplying)
    }

    /// The pair the coach screen diagnoses with this — device holds önd+,
    /// server says subscription required — is only readable if the reply's
    /// source is published, and only trustworthy if it dies with the question
    /// it answered.
    @Test("The reply's source is published, and cleared when the next send starts")
    func replySourceIsPublishedPerReply() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("Why is the coach quiet?")
        try await settle(until: { model.isReplying })
        #expect(model.lastReplySource == nil, "no verdict before the reply")

        script.yield(AssistantChunk(
            text: "The coach is part of a subscription.",
            source: .subscriptionRequired
        ))
        script.finish()
        try await settle(until: { !model.isReplying })
        #expect(model.lastReplySource == .subscriptionRequired)

        model.send("And now?")
        try await settle(until: { model.isReplying })
        #expect(model.lastReplySource == nil, "a stale verdict never outlives its question")
        script.finish()
        try await settle(until: { !model.isReplying })
    }

    /// The view's onDisappear path: cancel stops the stream, so no request
    /// outlives the screen, and what already arrived stays readable.
    @Test("Cancel stops the stream and keeps what arrived")
    func cancelStopsTheStream() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("hello")
        script.yield(AssistantChunk(text: "The first part ", source: .model))
        try await settle(until: { model.transcript.count == 2 })

        model.cancel()
        try await settle(until: { !model.isReplying })

        #expect(!model.isReplying)
        #expect(
            model.transcript.last?.text == "The first part ",
            "what arrived stays readable; cancellation adds no apology"
        )
    }

    /// Offline is one quiet sentence in the coach's row, marked as the failure
    /// it is so the transcript can offer the question again, and the composer
    /// stays alive either way.
    @Test("A failure before the reply is one quiet sentence, and sending still works")
    func failureLeavesAQuietSentence() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("hello")
        script.finish(throwing: AssistantRepositoryError.transport(.stub("no network")))
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript[1].role == .coach)
        #expect(model.transcript[1].text == CoachChatModel.unavailableReply)
        #expect(model.transcript[1].isFailed, "the row the retry hangs under")
        #expect(!model.transcript[0].isFailed, "the question itself did not fail")
        #expect(!model.isReplying, "the composer is live again")

        model.send("still there?")
        try await settle(until: { model.transcript.count == 3 })
        #expect(model.transcript.count == 3, "the next question goes through untouched")

        let next = try #require(script.calls.last)
        #expect(
            next.history.map(\.text) == ["hello"],
            "the apology is this app talking, so the coach never reads it back"
        )
    }

    /// A reply that breaks mid-answer keeps what arrived, with no quiet
    /// sentence stitched onto a paragraph the person is reading.
    @Test("A break mid-reply keeps the text that arrived")
    func midStreamFailureKeepsText() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("hello")
        script.yield(AssistantChunk(text: "The mechanism is ", source: .model))
        script.finish(throwing: AssistantRepositoryError.transport(.stub("the stream broke")))
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript[1].text == "The mechanism is ")
        #expect(!model.transcript[1].isFailed, "half an answer is an answer, not a failure")
        #expect(!model.isReplying)
    }

    /// The "Try again" the transcript draws under a failed reply. The apology
    /// and the question it stood for both go, and the question is asked again
    /// under its own id, so the screen keeps the exchange it pinned.
    @Test("Retry asks the last question again and clears the failed turn")
    func retryReplacesTheFailedTurn() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("Why is my breath short?")
        let question = try #require(model.transcript.first?.id)
        script.finish(throwing: AssistantRepositoryError.transport(.stub("no network")))
        try await settle(until: { !model.isReplying })

        model.retry()
        // The second tap stands for a double tap on the button.
        model.retry()
        try await settle(until: { model.isReplying })

        #expect(model.transcript.count == 1, "the apology is gone and the question stands")
        #expect(model.transcript[0].id == question, "the pinned question keeps its identity")
        #expect(script.calls.count == 2, "one resend, not two")

        let resend = try #require(script.calls.last)
        #expect(resend.message == "Why is my breath short?")
        #expect(resend.history.isEmpty, "the retried question is asked from a clean slate")

        script.yield(AssistantChunk(text: "A longer exhale.", source: .model))
        script.finish()
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.map(\.role) == [.person, .coach])
        #expect(model.transcript[1].text == "A longer exhale.")
        #expect(!model.transcript[1].isFailed)
    }

    /// Retry is the failed row's own affordance: nothing else offers it, and a
    /// call with an answer in place must not ask the same question twice.
    @Test("Retry does nothing where the last reply landed")
    func retryIgnoresAnAnsweredTurn() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("first")
        script.yield(AssistantChunk(text: "An answer.", source: .model))
        script.finish()
        try await settle(until: { !model.isReplying })

        model.retry()

        #expect(model.transcript.count == 2, "the answered exchange is untouched")
        #expect(script.calls.count == 1, "no second question")
        #expect(!model.isReplying)
    }

    /// The history sent with each message is the transcript *before* that
    /// message — the server appends the new message itself, and doubling it
    /// would have the coach answer the question twice.
    @Test("Each send carries the prior transcript as history")
    func sendCarriesPriorHistory() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("first")
        script.yield(AssistantChunk(text: "An answer.", source: .model))
        script.finish()
        try await settle(until: { !model.isReplying })

        model.send("second")
        try await settle(until: { script.calls.count == 2 })

        let call = try #require(script.calls.last)
        #expect(call.message == "second")
        #expect(call.history.map(\.text) == ["first", "An answer."])
        #expect(call.history.map(\.role) == [.person, .coach])
    }
}
