import Foundation
import Observation

/// The list of conversations with the coach: what the Coach tab's root shows,
/// and where a chat is created or deleted.
///
/// Separate from ``CoachChatModel`` so list invalidation never couples to a
/// streaming reply's per-chunk republish: the list re-reads the store when it
/// appears and when a pushed chat pops, which is exactly when a title or a
/// recency can have changed.
@MainActor
@Observable
public final class ConversationListModel {
    /// Most recently updated first.
    public private(set) var conversations: [Conversation] = []

    private let store: any ConversationStoring

    public init(store: any ConversationStoring) {
        self.store = store
    }

    /// Re-reads the store.
    public func load() async {
        conversations = await store.conversations()
    }

    /// Removes one conversation from the store and the list.
    public func delete(_ id: Conversation.ID) async {
        await store.remove(id)
        conversations.removeAll { $0.id == id }
    }

    /// A fresh conversation, in memory only: the store refuses to persist an
    /// empty one, so it exists nowhere until its first message is sent.
    public func newConversation() -> Conversation {
        Conversation()
    }
}
