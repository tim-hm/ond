import Foundation
import os

/// The identity a device is given rather than mints: the watch receives the
/// phone's anonymous id over WatchConnectivity. It never mints — two ids for
/// one person would split their journey, with wrist sessions accumulating
/// against a stranger the phone can never see. Until the phone has been in
/// range once, `userId()` answers nil; the watch stays usable and the sync waits.
public final class ProvisionedUserIdentityStore: UserIdentityStore {
    private static let logger = Logger(category: "identity")

    /// What the store has been found to hold. Three states rather than an
    /// optional, because "nobody has looked yet" and "there is nothing there"
    /// are different answers and only one of them is worth re-asking.
    private enum Resolution: Sendable {
        case unread
        /// Confirmed empty. Cached like an id, and safe to: `provision` is the
        /// only writer in this process and updates this on its way past, so
        /// there is nothing a second read could discover. A watch that never
        /// meets its phone would otherwise pay a Keychain round-trip on every
        /// RPC it ever makes, forever.
        case absent
        case present(UserId)
    }

    private let storage: any IdentityStorage
    private let credentials: SessionCredentialCache
    /// Same reasoning as the minting store's: the reader is a synchronous
    /// interceptor on every request's path, so it must not hop or block.
    private let cached = OSAllocatedUnfairLock<Resolution>(initialState: .unread)

    /// - Parameter service: defaults to the running bundle — on the watch its
    ///   own, because the id it holds is a copy of the phone's, not a shared
    ///   item. `account` and `credentialAccount` match the phone's names, so
    ///   both devices file the same things under the same names.
    public convenience init(
        service: String = Bundle.main.bundleIdentifier ?? "xyz.holmie.ond.watchkitapp",
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

    /// Stores what the phone sent. Once the identity the devices share is bound
    /// to an Apple account, every request naming it is refused without the
    /// credential. A phone that has signed out sends nil, and the wrist stops
    /// presenting a value the server has revoked.
    public func adopt(sessionCredential credential: String?) {
        credentials.adopt(credential)
    }

    public func userId() -> UserId? {
        switch cached.withLock({ $0 }) {
        case .unread: break
        case .absent: return nil
        case let .present(id): return id
        }

        guard let stored = storage.read() else {
            cached.withLock { $0 = .absent }
            return nil
        }

        cached.withLock { $0 = .present(stored) }
        return stored
    }

    /// Adopts the id the phone sent, replacing a different stored one: the phone
    /// is the authority, and unacknowledged wrist sessions sync under the new
    /// id. A failed write leaves the identity alone — the phone re-sends on
    /// every foreground, and the last stored id beats one the next launch forgets.
    /// - Returns: whether the stored identity changed — the signal to kick a sync.
    @discardableResult
    public func adopt(userId id: UserId) -> Bool {
        guard userId() != id else { return false }

        guard storage.replace(with: id) else {
            Self.logger.error("the handed-over identity could not be stored")
            return false
        }

        cached.withLock { $0 = .present(id) }
        return true
    }
}
