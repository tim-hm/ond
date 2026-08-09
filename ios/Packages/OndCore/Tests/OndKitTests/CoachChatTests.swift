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

    /// The pair the coach screen diagnoses with this — device holds Coach,
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

    /// Offline is one quiet sentence in the coach's row, and the composer
    /// stays alive: the next send works without any retry affordance.
    @Test("A failure before the reply is one quiet sentence, and sending still works")
    func failureLeavesAQuietSentence() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("hello")
        script.finish(throwing: AssistantRepositoryError.transport("no network"))
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript[1].role == .coach)
        #expect(model.transcript[1].text == CoachChatModel.unavailableReply)
        #expect(!model.isReplying, "the composer is live again")

        model.send("still there?")
        try await settle(until: { model.transcript.count == 3 })
        #expect(model.transcript.count == 3, "the next question goes through untouched")
    }

    /// A reply that breaks mid-answer keeps what arrived, with no quiet
    /// sentence stitched onto a paragraph the person is reading.
    @Test("A break mid-reply keeps the text that arrived")
    func midStreamFailureKeepsText() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("hello")
        script.yield(AssistantChunk(text: "The mechanism is ", source: .model))
        script.finish(throwing: AssistantRepositoryError.transport("the stream broke"))
        try await settle(until: { !model.isReplying })

        #expect(model.transcript.count == 2)
        #expect(model.transcript[1].text == "The mechanism is ")
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
