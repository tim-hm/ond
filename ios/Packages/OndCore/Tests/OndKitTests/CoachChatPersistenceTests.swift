import Foundation
@testable import OndKit
import Testing

/// The half of the coach-chat surface persistence and offers added:
/// `CoachChatTests` keeps the streaming and voice behaviours, this suite holds
/// what a stored conversation and an exercise offer changed.
@Suite("Coach chat persistence and offers")
@MainActor
struct CoachChatPersistenceTests {
    /// A history turn longer than the message bound is clamped before it is
    /// sent: the server refuses an over-long turn outright, coach replies
    /// regularly run past the bound, and a persisted transcript would replay
    /// that refusal on every send forever.
    @Test("Over-long history turns are clamped before sending")
    func overlongHistoryTurnsAreClamped() async throws {
        let script = ChatScript()
        let longReply = String(repeating: "x", count: ChatTurn.maxMessageLength + 200)
        let conversation = Conversation(turns: [
            ChatTurn(role: .person, text: "first"),
            ChatTurn(role: .coach, text: longReply),
        ])
        let model = chatModel(script, conversation: conversation)

        model.send("second")
        try await settle(until: { !script.calls.isEmpty })

        let call = try #require(script.calls.last)
        #expect(call.history.count == 2)
        #expect(call.history[1].text.count == ChatTurn.maxMessageLength)
    }

    /// A model seeded from a stored conversation exposes its turns — the
    /// re-opened chat reads exactly where it left off.
    @Test("A stored conversation seeds the transcript")
    func storedConversationSeedsTranscript() {
        let conversation = Conversation(turns: [
            ChatTurn(role: .person, text: "hello"),
            ChatTurn(role: .coach, text: "hello back"),
        ])
        let model = chatModel(ChatScript(), conversation: conversation)

        #expect(model.transcript.map(\.text) == ["hello", "hello back"])
    }

    /// The offer rides the reply turn under the reply's own id — the bubble
    /// grows a card, no row is replaced — and a second offer is ignored: the
    /// contract is at most one, and a misbehaving stream must not swap the
    /// card out from under a tap.
    @Test("An offer attaches to the growing reply, and only the first counts")
    func offerAttachesToReply() async throws {
        let script = ChatScript()
        let model = chatModel(script)
        let offered = ExerciseOffer(techniqueSlug: "box-breathing")

        model.send("what should I do?")
        script.yield(AssistantChunk(text: "Try box breathing.", source: .model))
        try await settle(until: { model.transcript.count == 2 })
        let replyId = model.transcript[1].id

        script.yield(AssistantChunk(text: "", source: .model, offer: offered))
        try await settle(until: { model.transcript.last?.offer != nil })

        script.yield(AssistantChunk(
            text: " Or not.",
            source: .model,
            offer: ExerciseOffer(techniqueSlug: "wim-hof")
        ))
        script.finish()
        try await settle(until: { !model.isReplying })

        let reply = try #require(model.transcript.last)
        #expect(reply.id == replyId, "the offer grows the same turn")
        #expect(reply.text == "Try box breathing. Or not.")
        #expect(reply.offer == offered, "the first offer wins")
    }

    /// The contract says an offer follows prose, but a reply that leads with
    /// one still renders: the coach turn exists from the first chunk, text or
    /// not.
    @Test("An offer before any text still yields a coach turn")
    func offerBeforeTextYieldsTurn() async throws {
        let script = ChatScript()
        let model = chatModel(script)

        model.send("go on then")
        script.yield(AssistantChunk(
            text: "",
            source: .model,
            offer: ExerciseOffer(techniqueSlug: "box-breathing")
        ))
        try await settle(until: { model.transcript.count == 2 })

        script.yield(AssistantChunk(text: "Here you are.", source: .model))
        script.finish()
        try await settle(until: { !model.isReplying })

        let reply = try #require(model.transcript.last)
        #expect(reply.role == .coach)
        #expect(reply.offer?.techniqueSlug == "box-breathing")
        #expect(reply.text == "Here you are.")
        #expect(model.transcript.count == 2, "the leading offer opened the one reply turn")
    }

    /// The two persistence points of a happy send: the person's turn lands in
    /// the store before any reply, and the finished reply lands after it —
    /// with the conversation's recency bumped.
    @Test("Send persists the question, and the finished reply persists after it")
    func sendAndFinishPersist() async throws {
        let script = ChatScript()
        let store = InMemoryConversationStore()
        let conversation = Conversation(updatedAt: .distantPast)
        let model = chatModel(script, store: store, conversation: conversation)

        model.send("hello")
        try await settle(until: { store.saves == 1 })
        #expect(store.all.first?.turns.map(\.text) == ["hello"])

        script.yield(AssistantChunk(text: "An answer.", source: .model))
        script.finish()
        try await settle(until: { store.saves == 2 })

        let stored = try #require(store.all.first)
        #expect(stored.turns.map(\.text) == ["hello", "An answer."])
        #expect(stored.updatedAt > .distantPast, "recency is bumped on persist")
        #expect(store.all.count == 1, "the saves upsert one conversation")
    }

    /// The mid-stream endings both keep what arrived on disk: a break persists
    /// the partial reply, and cancel — the screen going away — does too.
    @Test("A break or a cancel mid-reply persists the partial text")
    func interruptionsPersistPartials() async throws {
        let script = ChatScript()
        let store = InMemoryConversationStore()
        let model = chatModel(script, store: store)

        model.send("hello")
        script.yield(AssistantChunk(text: "The mechanism is ", source: .model))
        script.finish(throwing: AssistantRepositoryError.transport("the stream broke"))
        try await settle(until: { store.saves == 2 })
        #expect(store.all.first?.turns.last?.text == "The mechanism is ")

        model.send("and then?")
        script.yield(AssistantChunk(text: "Half an ans", source: .model))
        try await settle(until: { model.transcript.count == 4 })
        model.cancel()
        try await settle(until: { store.all.first?.turns.count == 4 })
        #expect(store.all.first?.turns.last?.text == "Half an ans")
    }
}
