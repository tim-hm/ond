import Foundation
import os
import Security

/// One Keychain entry, and the only place `Security` is called.
///
/// Two things are kept there and both go through here: the anonymous id, and —
/// once this install has signed in with Apple — the credential that proves it.
/// Two copies of a `SecItemAdd` query would be two places for the service, the
/// accessibility class or the item class to drift, and the pair have to agree:
/// a credential the device can read at a moment the id is unreadable is a
/// request that proves an identity it cannot name.
///
/// `kSecClassGenericPassword` is chosen for what it survives as much as for what
/// it protects. A Keychain item outlives the app's container, so deleting and
/// reinstalling returns the same person to their own history rather than
/// stranding it behind an id nothing can reach.
///
/// Values are `String` rather than the types above it because that is what the
/// Keychain stores; `KeychainIdentityItem` is the UUID reading of one of them.
struct KeychainItem: Sendable {
    private static let logger = Logger(category: "identity")

    let service: String
    let account: String

    func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            // Not finding one is the normal state on first launch, so only a
            // real failure is worth a line in the log.
            if status != errSecItemNotFound {
                Self.logger.error("failed to read `\(account, privacy: .public)`: \(status)")
            }
            return nil
        }

        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            Self.logger.error("`\(account, privacy: .public)` is not readable text")
            return nil
        }

        return text
    }

    /// Writes `value` where there is nothing stored, and answers with whatever
    /// the item holds afterwards.
    ///
    /// The `errSecDuplicateItem` branch is what makes minting safe against a
    /// race: another caller wrote between this one's read and this write, theirs
    /// is the stored value, and both callers have to agree on it.
    ///
    /// - Returns: `value`, the one that beat it there, or nil where neither the
    ///   write nor the re-read could be made.
    func insert(_ value: String) -> String? {
        switch add(value) {
        case errSecSuccess:
            return value

        case errSecDuplicateItem:
            return read()

        case let status:
            Self.logger.error("failed to store `\(account, privacy: .public)`: \(status)")
            return nil
        }
    }

    /// Stores `value` whatever is already there — the handover path, where
    /// something else is the authority on what this should be.
    ///
    /// - Returns: whether the item now holds `value`.
    func replace(with value: String) -> Bool {
        switch add(value) {
        case errSecSuccess:
            return true

        case errSecDuplicateItem:
            let status = SecItemUpdate(
                baseQuery() as CFDictionary,
                [kSecValueData as String: Data(value.utf8)] as CFDictionary
            )
            if status != errSecSuccess {
                Self.logger.error("failed to replace `\(account, privacy: .public)`: \(status)")
            }
            return status == errSecSuccess

        case let status:
            Self.logger.error("failed to store `\(account, privacy: .public)`: \(status)")
            return false
        }
    }

    /// Deletes the item, which only the credential ever does.
    ///
    /// An identity is never removed — it is replaced, because an install with no
    /// id would mint a new one and orphan whatever is filed under the old. A
    /// credential is the opposite: signing out means this device holds nothing
    /// that proves the account, and leaving a revoked value behind would have
    /// every later request present something the server has already deleted.
    ///
    /// - Returns: whether the item is gone, which a missing one already is.
    @discardableResult
    func remove() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Self.logger.error("failed to delete `\(account, privacy: .public)`: \(status)")
            return false
        }

        return true
    }

    /// Writes `value` only where there is nothing stored, reporting the raw
    /// status so a caller can tell a lost race (`errSecDuplicateItem`) from a
    /// failure.
    private func add(_ value: String) -> OSStatus {
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(value.utf8)
        // Readable once the device has been unlocked at all, rather than only
        // while it is unlocked: the sync queue drains in the background, and a
        // call that cannot read the identity cannot attribute what it sends.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
