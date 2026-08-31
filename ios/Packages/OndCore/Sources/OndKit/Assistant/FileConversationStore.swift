import Foundation

/// Reads and writes the coach conversations, the seam the chat models are
/// written against so tests need no disk.
public protocol ConversationStoring: Sendable {
    /// Every conversation, most recently updated first.
    func conversations() async -> [Conversation]

    /// Upserts by id. A conversation with no turns is dropped, not saved — an
    /// opened-and-abandoned "new chat" leaves nothing behind.
    func save(_ conversation: Conversation) async

    /// Removes every conversation named, in one write. Unknown ids are a
    /// no-op: a delete raced by another delete has already succeeded.
    func remove(_ ids: Set<Conversation.ID>) async
}

/// The conversations, in one JSON file in Application Support.
/// `FileSessionStore`'s arrangement without the tombstones: conversations
/// never sync — the server keeps no transcript at all — so a delete here is
/// simply a removal.
public actor FileConversationStore: ConversationStoring, PersonalStore {
    private let file: JSONFileStore<Conversation>

    /// `directory` defaults to the app's Application Support and exists to be
    /// overridden by tests, which pass a temporary directory per suite.
    public init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(
            directory: directory,
            fileName: "conversations.json",
            category: "chat-store"
        )
    }

    public func conversations() -> [Conversation] {
        // Sorted here rather than kept sorted on disk: the file holds upsert
        // order, and the recency contract is this method's, stated once.
        file.load().sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ conversation: Conversation) {
        guard !conversation.turns.isEmpty else { return }

        var all = file.load()
        if let index = all.firstIndex(where: { $0.id == conversation.id }) {
            all[index] = conversation
        } else {
            all.append(conversation)
        }
        file.save(all)
    }

    public func remove(_ ids: Set<Conversation.ID>) {
        let all = file.load()
        let kept = all.filter { !ids.contains($0.id) }
        guard kept.count != all.count else { return }
        file.save(kept)
    }

    public func erase() {
        file.erase()
    }
}
