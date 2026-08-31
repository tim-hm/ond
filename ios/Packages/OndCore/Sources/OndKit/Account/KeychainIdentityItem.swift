import Foundation
import os

/// The anonymous id as the Keychain holds it: a `KeychainItem` read as a
/// UUID. A thin reading rather than a store, so the id and the credential
/// beside it are written by one description of a Keychain item. What this
/// adds is the parse — a stored non-UUID is reported, never overwritten.
struct KeychainIdentityItem: Sendable {
    private static let logger = Logger(category: "identity")

    private let item: KeychainItem

    init(service: String, account: String) {
        item = KeychainItem(service: service, account: account)
    }

    func read() -> UserId? {
        guard let stored = item.read() else { return nil }

        guard let id = UserId(uuidString: stored) else {
            // Something else wrote this item, or it was truncated. Reporting it
            // rather than overwriting: an identity is not ours to discard, and a
            // fresh one would silently orphan whatever is stored against the old.
            Self.logger.error("the stored anonymous identity is not a UUID")
            return nil
        }

        return id
    }

    /// - Returns: `id`, the value that beat it there, or nil where neither the
    ///   write nor the re-read could be made — which is the Keychain being
    ///   unreachable, and leaves this install anonymous for now rather than
    ///   inventing an identity it cannot store.
    func insert(_ id: UserId) -> UserId? {
        item.insert(id.uuidString).flatMap(UserId.init(uuidString:))
    }

    /// - Returns: whether the item now holds `id`.
    func replace(with id: UserId) -> Bool {
        item.replace(with: id.uuidString)
    }
}
