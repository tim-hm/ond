import Foundation
import os

/// This install's identity and, after sign-in, the credential that proves it.
/// They live together because the server refuses a bound id every request that
/// cannot present the credential. A protocol so the watch can store what the
/// phone sent it, and so tests need not reach the real Keychain.
public protocol UserIdentityStore: Sendable {
    /// The id this install attributes its work to, or nil while it has none.
    /// The phone mints one on first use; the watch waits to be handed the
    /// phone's. Callers treat nil as anonymous, not as a failure — an absent
    /// identity costs only the scoped RPCs.
    func userId() -> UserId?

    /// Makes `id` the identity from now on, in the cache as well as the store.
    /// Sign-in can answer with an older, merged-into identity; the server
    /// refuses the id left behind, so a swap that reached the Keychain alone
    /// would stamp the dead id on every request until the next launch.
    /// - Returns: true when the identity changed — the signal to tell copies.
    @discardableResult
    func adopt(userId id: UserId) -> Bool

    /// What proves `userId()` to the server, or nil while this install has
    /// never signed in. Read beside the id on every request. Nil is ordinary,
    /// not a failure: an unbound identity has nothing to prove.
    func sessionCredential() -> String?

    /// Makes `credential` what this install proves itself with, or clears it.
    /// Write it before the id it belongs to, everywhere both change: the
    /// interceptor reads the two separately, and the new id with the old
    /// credential is the one combination the server refuses.
    func adopt(sessionCredential credential: String?)
}

extension UserIdentityStore {
    /// The identity as the transport sends it. `OndAPI` sits below this target
    /// and cannot name `UserId`, so every repository hands the interceptor this
    /// rather than narrowing for itself. Deliberately not public: an app target
    /// that could reach a raw id is the state this type exists to remove.
    func wireUserId() -> UUID? {
        userId()?.rawValue
    }
}

/// A seam over the Keychain, so the identity rules can be pinned by host
/// tests — where the real Keychain would mean an unsigned process writing to a
/// developer's login keychain.
protocol IdentityStorage: Sendable {
    func read() -> UserId?

    /// Stores `id` only where there is nothing stored.
    ///
    /// - Returns: what the store holds afterwards — `id`, or the value a writer
    ///   that got there first put in it, or nil where the write failed.
    func insert(_ id: UserId) -> UserId?

    /// - Returns: whether the store now holds `id`.
    func replace(with id: UserId) -> Bool
}

extension KeychainIdentityItem: IdentityStorage {}

/// `userId()` mints and stores an id on first ask; nil means the Keychain is
/// unreachable. The id is cached for the process because a Keychain read is an
/// XPC round-trip on every request path; only a successful read fills the
/// cache, and a racing mint re-reads via `KeychainIdentityItem.insert`. Keep
/// one instance per process — a second cache stamps the merged-away id.
public final class KeychainUserIdentityStore: UserIdentityStore {
    private static let logger = Logger(category: "identity")

    private let storage: any IdentityStorage
    private let credentials: SessionCredentialCache
    /// A lock, not an actor: the caller is a synchronous interceptor on the
    /// request path. Held across the storage call on purpose — released around
    /// the read, a request could resolve the old id, wait out an adopt, and
    /// cache the deleted identity over its replacement for the life of the
    /// process.
    private let cached = OSAllocatedUnfairLock<UserId?>(initialState: nil)

    /// - Parameters:
    ///   - service: defaults to the running bundle so the phone and watch
    ///     apps, separate bundles, do not collide before the handover.
    ///   - credentialAccount: a second Keychain item, so reading the id costs
    ///     nothing for installs that never hold a credential.
    public convenience init(
        service: String = Bundle.main.bundleIdentifier ?? "xyz.holmie.ond",
        account: String = "anonymous-user-id",
        credentialAccount: String = "session-credential"
    ) {
        self.init(
            storage: KeychainIdentityItem(service: service, account: account),
            credentials: KeychainItem(service: service, account: credentialAccount)
        )
    }

    init(storage: any IdentityStorage, credentials: any CredentialStorage) {
        self.storage = storage
        self.credentials = SessionCredentialCache(storage: credentials)
    }

    public func sessionCredential() -> String? {
        credentials.credential()
    }

    public func adopt(sessionCredential credential: String?) {
        credentials.adopt(credential)
    }

    public func userId() -> UserId? {
        cached.withLock { remembered in
            if let remembered {
                return remembered
            }

            remembered = storage.read() ?? storage.insert(UserId(rawValue: UUID()))
            return remembered
        }
    }

    /// The cache is written even when the Keychain write fails: the server has
    /// already merged, the old id names a deleted row, and sending it on loses
    /// history — so a failed write logs rather than refuses. One lock
    /// acquisition, deciding included, so no request resolves the stale id in
    /// a gap. Nothing mints here: `userId()` would mint only to overwrite.
    @discardableResult
    public func adopt(userId id: UserId) -> Bool {
        cached.withLock { remembered in
            let current = remembered ?? storage.read()
            guard current != id else {
                remembered = current
                return false
            }

            remembered = id

            if !storage.replace(with: id) {
                Self.logger.error("the adopted identity could not be stored")
            }

            return true
        }
    }
}
