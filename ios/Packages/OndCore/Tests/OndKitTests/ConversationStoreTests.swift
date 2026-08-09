import Foundation
import OndKit
import Testing

@Suite("Keeping coach conversations on the device")
struct ConversationStoreTests {
    /// A directory of this suite's own, so a run never reads what a previous
    /// one or the host's real app support directory left behind.
    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "ond-conversation-store-\(UUID().uuidString)")
    }

    private func conversation(
        asked: String = "What helps with sleep?",
        at updated: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Conversation {
        Conversation(
            createdAt: updated,
            updatedAt: updated,
            turns: [
                ChatTurn(role: .person, text: asked),
                ChatTurn(
                    role: .coach,
                    text: "A longer exhale.",
                    offer: ExerciseOffer(
                        techniqueSlug: "extended-exhale",
                        overrides: TechniqueOverrides(
                            phaseDurationsMs: [[4000, 6000]],
                            stageCycles: [8],
                            rounds: 2
                        )
                    )
                ),
            ]
        )
    }

    /// The device's copy is the only copy, so every field has to survive the
    /// file — the offer and its dialling included, or a re-opened chat shows
    /// a reply that lost its card.
    @Test("A conversation survives the round trip through disk intact")
    func roundTripsAConversation() async {
        let directory = temporaryDirectory()
        let written = conversation()

        await FileConversationStore(directory: directory).save(written)
        let read = await FileConversationStore(directory: directory).conversations()

        #expect(read == [written])
    }

    @Test("A fresh store holds nothing")
    func startsEmpty() async {
        let store = FileConversationStore(directory: temporaryDirectory())
        #expect(await store.conversations().isEmpty)
    }

    /// Saves upsert by id, and the list answers most recently updated first —
    /// the order the Coach tab shows.
    @Test("Saves upsert, and the list is most recent first")
    func upsertsAndSortsByRecency() async {
        let store = FileConversationStore(directory: temporaryDirectory())
        let older = conversation(asked: "older", at: Date(timeIntervalSince1970: 1000))
        var newer = conversation(asked: "newer", at: Date(timeIntervalSince1970: 2000))

        await store.save(older)
        await store.save(newer)
        #expect(await store.conversations().map(\.title) == ["newer", "older"])

        newer.turns.append(ChatTurn(role: .person, text: "again"))
        await store.save(newer)

        let all = await store.conversations()
        #expect(all.count == 2, "a re-save replaces, never duplicates")
        #expect(all.first?.turns.count == 3)
    }

    /// An opened-and-abandoned "new chat" must leave nothing behind: the
    /// store refuses a conversation with no turns.
    @Test("An empty conversation is not persisted")
    func refusesEmptyConversations() async {
        let store = FileConversationStore(directory: temporaryDirectory())
        await store.save(Conversation())
        #expect(await store.conversations().isEmpty)
    }

    @Test("Removing deletes, and removing the unknown is a no-op")
    func removes() async {
        let store = FileConversationStore(directory: temporaryDirectory())
        let kept = conversation(asked: "kept")
        let deleted = conversation(asked: "deleted")

        await store.save(kept)
        await store.save(deleted)
        await store.remove([deleted.id])
        #expect(await store.conversations() == [kept])

        await store.remove([UUID()])
        #expect(await store.conversations() == [kept])
    }

    /// The deletion registry's contract: erase leaves the store as a fresh
    /// install would find it, cache and file both.
    @Test("Erase leaves a fresh install")
    func erases() async {
        let directory = temporaryDirectory()
        let store = FileConversationStore(directory: directory)

        await store.save(conversation())
        await store.erase()

        #expect(await store.conversations().isEmpty)
        #expect(await FileConversationStore(directory: directory).conversations().isEmpty)
    }

    /// A corrupt file reads as empty rather than throwing, and the next save
    /// works — unreadable history is not worth failing the whole tab over.
    @Test("A corrupt file reads as empty and the store keeps working")
    func survivesCorruption() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appending(path: "conversations.json"))

        let store = FileConversationStore(directory: directory)
        #expect(await store.conversations().isEmpty)

        await store.save(conversation())
        #expect(await store.conversations().count == 1)
    }
}

@Suite("The conversation list model")
@MainActor
struct ConversationListModelTests {
    @Test("Load reads the store recent-first, and delete removes everywhere")
    func loadsAndDeletes() async {
        let directory = URL.temporaryDirectory
            .appending(path: "ond-conversation-list-\(UUID().uuidString)")
        let store = FileConversationStore(directory: directory)
        let older = Conversation(
            updatedAt: Date(timeIntervalSince1970: 1000),
            turns: [ChatTurn(role: .person, text: "older")]
        )
        let newer = Conversation(
            updatedAt: Date(timeIntervalSince1970: 2000),
            turns: [ChatTurn(role: .person, text: "newer")]
        )
        await store.save(older)
        await store.save(newer)

        let model = ConversationListModel(store: store)
        await model.load()
        #expect(model.conversations.map(\.title) == ["newer", "older"])

        await model.delete(newer.id)
        #expect(model.conversations.map(\.title) == ["older"])
        #expect(await store.conversations().map(\.title) == ["older"])
    }

    /// A new conversation exists only in memory until its first send — the
    /// list must not grow a row for a chat nobody started.
    @Test("A new conversation is not in the store")
    func newConversationIsInMemoryOnly() async {
        let store = FileConversationStore(
            directory: URL.temporaryDirectory
                .appending(path: "ond-conversation-new-\(UUID().uuidString)")
        )
        let model = ConversationListModel(store: store)

        _ = model.newConversation()
        await model.load()

        #expect(model.conversations.isEmpty)
    }
}
