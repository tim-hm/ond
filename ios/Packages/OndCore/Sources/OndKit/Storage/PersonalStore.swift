import Foundation

/// Something this device keeps about the person, and the one thing deleting an
/// account asks of it. The device has no cascade: the practice is spread over
/// session files, `UserDefaults` keys, in-memory copies, and notification
/// requests iOS holds. Each store answers for itself, and `AccountModel` is
/// handed the list rather than the knowledge.
public protocol PersonalStore: Sendable {
    /// Leaves this store exactly as a fresh install would find it.
    /// Both halves, always: whatever was written and whatever is cached in
    /// this process. A store that cleared its file and kept its `@Observable`
    /// copy goes on showing the erased person's practice for the life of the
    /// process. `UserIdentityStore.adopt` follows the same rule.
    func erase() async
}
