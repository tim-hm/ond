import Foundation
import os

/// Where the credential that proves a signed-in identity is kept. A seam
/// rather than the Keychain directly, for the reason `IdentityStorage` is
/// one: host tests must pin the rules above it without an unsigned process
/// writing to a developer's login keychain.
protocol CredentialStorage: Sendable {
    func read() -> String?

    /// - Returns: whether the store now holds `value`.
    func replace(with value: String) -> Bool

    /// - Returns: whether the store now holds nothing, which an empty one
    ///   already does.
    @discardableResult
    func remove() -> Bool
}

extension KeychainItem: CredentialStorage {}

/// The credential half of an identity store, shared by the phone's and the
/// watch's: the rule is the same on each and neither mints. Cached for the
/// life of the process because a synchronous interceptor reads it on every
/// request, and a Keychain read is an XPC round-trip. Three states, not an
/// optional, so "nobody has looked yet" and "not signed in" are told apart.
final class SessionCredentialCache: Sendable {
    private enum Resolution: Sendable {
        case unread
        case absent
        case present(String)
    }

    private let storage: any CredentialStorage
    /// `OSAllocatedUnfairLock` rather than an actor, and held across the storage
    /// call, for the reasons `KeychainUserIdentityStore` gives: the reader is on
    /// the request path and must not hop, and a swap that released the lock
    /// mid-way could cache a credential the server has already revoked over the
    /// one that replaced it.
    private let cached = OSAllocatedUnfairLock<Resolution>(initialState: .unread)

    init(storage: any CredentialStorage) {
        self.storage = storage
    }

    func credential() -> String? {
        cached.withLock { resolution in
            switch resolution {
            case .unread:
                guard let stored = storage.read() else {
                    resolution = .absent
                    return nil
                }
                resolution = .present(stored)
                return stored

            case .absent:
                return nil

            case let .present(credential):
                return credential
            }
        }
    }

    /// Makes `credential` what this install proves its identity with, or
    /// clears it. The cache is written whether or not the Keychain took the
    /// value: the server has already minted or revoked, so presenting the old
    /// credential fails every request. A failed write is an error line and a
    /// swap forgotten at the next launch, which signing in again repairs.
    func adopt(_ credential: String?) {
        cached.withLock { resolution in
            guard let credential else {
                resolution = .absent
                storage.remove()
                return
            }

            resolution = .present(credential)

            if !storage.replace(with: credential) {
                Logger(category: "identity")
                    .error("the session credential could not be stored")
            }
        }
    }
}
