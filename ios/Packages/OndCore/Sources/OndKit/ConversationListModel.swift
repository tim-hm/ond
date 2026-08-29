import Foundation
import Observation

/// The list of conversations with the coach: what the Coach tab's root
/// shows, and where a chat is created or deleted. Separate from
/// ``CoachChatModel`` so list invalidation never couples to a streaming
/// reply's per-chunk republish; it re-reads the store on appear and when a
/// pushed chat pops.
@MainActor
@Observable
public final class ConversationListModel {
    /// Most recently updated first.
    public private(set) var conversations: [Conversation] = []

    private let store: any ConversationStoring

    /// Over the store alone — the list is a read model, and everything it
    /// shows is derived from what the store answers.
    public init(store: any ConversationStoring) {
        self.store = store
    }

    /// Re-reads the store.
    public func load() async {
        conversations = await store.conversations()
    }

    /// Removes one conversation from the store and the list.
    public func delete(_ id: Conversation.ID) async {
        await delete(ids: [id])
    }

    /// The swipe-to-delete shape: rows by their offsets in the published
    /// list. Here rather than in the view, so the view never indexes into
    /// model state to orchestrate a mutation the model owns. Out-of-range
    /// offsets are skipped, not trapped — the list can be re-sorted or
    /// shrunk by a landing save between the swipe and this running.
    public func delete(at offsets: IndexSet) async {
        let ids = Set(offsets.compactMap { offset in
            conversations.indices.contains(offset) ? conversations[offset].id : nil
        })
        await delete(ids: ids)
    }

    private func delete(ids: Set<Conversation.ID>) async {
        guard !ids.isEmpty else { return }
        await store.remove(ids)
        conversations.removeAll { ids.contains($0.id) }
    }

    /// A fresh conversation, in memory only: the store refuses to persist an
    /// empty one, so it exists nowhere until its first message is sent.
    public func newConversation() -> Conversation {
        Conversation()
    }
}
