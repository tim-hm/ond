import Foundation
import os
import Security

/// One Keychain entry, and the only place `Security` is called. The
/// anonymous id and the Apple session credential both go through here — two
/// copies of a `SecItemAdd` query would let the pair drift, and the pair
/// must agree. `kSecClassGenericPassword` outlives the app's container, so a
/// reinstall returns the same person to their own history.
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
    /// the item holds afterwards. The `errSecDuplicateItem` branch makes
    /// minting safe against a race: another caller wrote first, theirs is the
    /// stored value, and both callers must agree on it.
    /// - Returns: `value`, the one that beat it there, or nil if neither wrote.
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

    /// Deletes the item, which only the credential ever does: an identity is
    /// replaced, never removed — an install with no id would mint a new one
    /// and orphan the old — while a revoked credential left behind would be
    /// presented on every later request.
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
