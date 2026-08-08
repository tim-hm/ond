import Foundation
import os

/// Where the credential that proves a signed-in identity is kept.
///
/// A seam rather than the Keychain directly, for the reason `IdentityStorage` is
/// one: the rules above it have to be pinnable by tests that run on the host,
/// where reaching the real Keychain means an unsigned process writing to a
/// developer's login keychain.
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
/// watch's.
///
/// One type for both because the rule is the same on each and neither mints:
/// the credential is issued by `AccountService.SignInWithApple` and arrives
/// either from that response or from the phone over WatchConnectivity. What
/// differs between the two devices — who may invent an id — has no counterpart
/// here.
///
/// Cached for the life of the process for the reason the id is: it is read by a
/// synchronous interceptor on the path of every request, and a Keychain read is
/// an XPC round-trip to `securityd`. Three states rather than an optional so
/// that "nobody has looked yet" and "this install has not signed in" are told
/// apart — the second is the overwhelmingly common one, and re-asking the
/// Keychain about it on every RPC forever is the cost that would buy nothing.
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

    /// Makes `credential` what this install proves its identity with, or clears
    /// it where there is nothing to prove.
    ///
    /// The cache is written whether or not the Keychain took the value, which is
    /// the same trade `KeychainUserIdentityStore.adopt` makes and for a sharper
    /// reason: by the time this is called the server has already minted the new
    /// credential or revoked the old one, so continuing to present what this
    /// device happens to still hold is refused on every request. A failed write
    /// is an error line and a swap this install forgets at the next launch,
    /// which signing in again repairs.
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
