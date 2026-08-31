import Foundation
import Observation
import os

/// Sign-in, sign-out, and account deletion — the identity swap all three
/// perform. The client is the authority on which id is live, so every path
/// that changes it changes it completely and ends by telling everything that
/// holds a copy. Sign-in may adopt an *older* identity the server has merged
/// this install's history into.
@MainActor
@Observable
public final class AccountModel {
    private static let logger = Logger(category: "account")

    /// Whether this install has bound an Apple account.
    ///
    /// Kept in `UserDefaults`, so a reinstall reads back `.localOnly` while the
    /// surviving Keychain identity may still be bound; the next sign-in answers
    /// `boundElsewhere` and `signIn` records it, so the state repairs itself.
    public private(set) var state: AccountState {
        didSet { defaults.set(state == .signedIn, forKey: Self.signedInKey) }
    }

    /// The anonymous identity this install's work is filed under — the only
    /// handle a local-only person can quote to support. Nil when the Keychain
    /// could not be read. Mirrored rather than computed: a computed read into a
    /// store registers no Observation dependency, so a retired id would keep
    /// showing. Reading it in the initialiser mints it on first launch.
    public private(set) var userId: UUID?

    /// What a person quotes to support: the first two groups of the id, twelve
    /// hex characters, lowercased. **Must match** the server's
    /// `obs::record_user_id` derivation, so a quoted prefix still finds the one
    /// row with a `LIKE` prefix. Never the whole id — that is a bearer
    /// credential for the account. Nil exactly when `userId` is.
    public var supportReference: String? {
        userId.map { String($0.uuidString.prefix(Self.supportReferenceLength)).lowercased() }
    }

    /// How far the current account action has got.
    ///
    /// One enum rather than a flag beside a reason: those two can say "working"
    /// and "failed" at the same time, and nothing but the order of each call
    /// path's assignments kept them apart.
    public enum Progress: Sendable, Equatable {
        case idle
        /// An account call is on the wire. Sign-in reaches Apple's key endpoint
        /// through the server on a cold key cache, so this is long enough to
        /// need saying.
        case working
        /// What went wrong, for the one screen that asked. The next attempt
        /// replaces it, since a stale reason beside a fresh button is worse
        /// than none.
        case failed(String)

        /// The reason a failed attempt gave, or nil. A projection of the case
        /// above, so it cannot disagree with it the way a separate stored
        /// property could.
        public var reason: String? {
            if case let .failed(reason) = self {
                reason
            } else {
                nil
            }
        }
    }

    public private(set) var progress: Progress = .idle

    /// Whether an account call is on the wire, so a button refuses to start a
    /// second one. A projection on `SubscriptionStore.isBusy`'s pattern, which
    /// keeps a view from matching the cases itself.
    public var isWorking: Bool {
        progress == .working
    }

    private static let signedInKey = "account.signedIn"

    /// How much of the id `supportReference` keeps: two groups of the canonical
    /// form, which is twelve hex characters and the hyphen between them.
    private static let supportReferenceLength = 13

    private let identity: any UserIdentityStore
    private let accounts: any AccountSyncing
    private let stores: [any PersonalStore]
    private let defaults: UserDefaults
    private let onIdentityChange: @MainActor () async -> Void

    /// - Parameter stores: everything on this device that holds something about
    ///   the person, for `deleteAccount` to empty. Listed by the composition
    ///   root: a store left off the list is a deletion that quietly is not one.
    /// - Parameter onIdentityChange: run after the identity has actually
    ///   changed, to tell everything holding a copy — the watch and the journey.
    public init(
        identity: any UserIdentityStore,
        accounts: any AccountSyncing,
        stores: [any PersonalStore],
        defaults: UserDefaults = .standard,
        onIdentityChange: @escaping @MainActor () async -> Void
    ) {
        self.identity = identity
        self.accounts = accounts
        self.stores = stores
        self.defaults = defaults
        self.onIdentityChange = onIdentityChange
        userId = identity.userId()
        // Assigning in an initialiser does not run `didSet`, which is what keeps
        // this from writing back the value it just read.
        state = defaults.bool(forKey: Self.signedInKey) ? .signedIn : .localOnly
    }

    /// Makes `id` the identity from now on, and republishes it. Every swap goes
    /// through here, because `userId` is a second copy of what the store holds.
    /// The credential (nil where there is nothing to prove) is written first:
    /// the interceptor reads the pair separately, and the reverse order is a
    /// bound id presenting a replaced credential. Returns whether it changed.
    @discardableResult
    private func swapIdentity(to id: UUID, proving credential: String?) -> Bool {
        identity.adopt(sessionCredential: credential)
        let changed = identity.adopt(id)
        userId = id
        return changed
    }

    /// Binds the Apple credential, adopts whatever identity comes back, and
    /// keeps the credential that identity now proves itself with. The adopt
    /// happens before anything else is awaited, so no request can be stamped
    /// with the merged-away id after the server has deleted it.
    public func signIn(identityToken: String) async {
        progress = .working
        // Every path that ends in a result records it; this returns the rest to
        // idle, so a later early return cannot leave a screen working forever.
        defer {
            if progress == .working {
                progress = .idle
            }
        }

        do {
            let adopted = try await accounts.signIn(identityToken: identityToken)
            state = .signedIn

            if swapIdentity(to: adopted.userId, proving: adopted.sessionCredential) {
                Self.logger.notice("adopted the identity this Apple account already had")
            }

            // Unconditionally: even a first sign-in, which keeps the caller's
            // id, changes everything about it — the row is bound now, and the
            // watch is refused every request until it too holds the credential.
            await onIdentityChange()
        } catch AccountRepositoryError.boundElsewhere {
            Self.logger.notice("this device is bound to a different Apple account")
            // The server has just told us something this install had forgotten:
            // it is bound, to somebody else's Apple account. Recording that is
            // what puts the sign-out in front of the person, which is the only
            // route from here to signing in as the account they offered.
            state = .signedIn
            progress = .failed(
                "This device is already signed in to a different Apple ID. "
                    + "Sign out first, then sign in again."
            )
        } catch {
            Self.logger.notice("sign-in failed: \(error.diagnostic, privacy: .public)")
            progress = .failed(error.localizedDescription)
        }
    }

    /// Fetches the nonce Apple must sign for one account action.
    ///
    /// One recovery path: a merge tombstone or a restored bound id without its
    /// credential makes the server refuse even the challenge RPC, so the
    /// install retries under a fresh anonymous identity before the sheet shows.
    public func beginAppleAuthorization(
        for purpose: AppleAuthorizationPurpose
    ) async throws -> AppleAuthorizationChallenge {
        do {
            return try await accounts.beginAppleAuthorization(for: purpose)
        } catch AccountRepositoryError.rejected where purpose == .signIn {
            return try await beginSignInAgainAsStranded()
        }
    }

    /// Retries a refused sign-in ceremony under a fresh anonymous identity.
    private func beginSignInAgainAsStranded() async throws -> AppleAuthorizationChallenge {
        let strandedId = identity.userId()
        let strandedCredential = identity.sessionCredential()

        Self.logger.notice(
            "the server refused this identity; retrying Apple authorization under a fresh one"
        )
        swapIdentity(to: UUID(), proving: nil)

        do {
            let nonce = try await accounts.beginAppleAuthorization(for: .signIn)
            await onIdentityChange()
            return nonce
        } catch {
            if let strandedId {
                swapIdentity(to: strandedId, proving: strandedCredential)
            }
            throw error
        }
    }

    /// Returns this install to local-only under a **fresh** anonymous identity.
    /// Keeping the old id would stay bound to the first Apple account: the next
    /// sign-in as somebody else is either refused or merges this practice into
    /// a stranger's row. The server is told first so the credential is revoked,
    /// but best effort — a person with no signal must still be able to sign out.
    public func signOut() async {
        progress = .working
        defer {
            if progress == .working {
                progress = .idle
            }
        }

        do {
            try await accounts.signOut()
        } catch {
            Self.logger.notice(
                "the session credential was not revoked: \(error.diagnostic, privacy: .public)"
            )
        }

        state = .localOnly

        if swapIdentity(to: UUID(), proving: nil) {
            await onIdentityChange()
        }
    }

    /// Erases the server row first (a failure can simply retry), adopts a fresh
    /// identity before any await — `identity::resolve` upserts any id, so one
    /// late request would recreate the erased person — then empties the local
    /// stores and tells the watch last. The App Store subscription survives.
    /// - Parameter identityToken: a fresh token when signed in, nil local-only.
    public func deleteAccount(identityToken: String?) async {
        progress = .working
        defer {
            if progress == .working {
                progress = .idle
            }
        }

        do {
            try await accounts.delete(identityToken: identityToken)
        } catch {
            Self.logger.notice(
                "account deletion failed: \(error.diagnostic, privacy: .public)"
            )

            if case .rejected? = error as? AccountRepositoryError, userId != nil {
                // A reinstall wipes `state` while the Keychain binding survives,
                // so a signed-in person can arrive believing they are local
                // only; the server refuses from its own row. Recording
                // `.signedIn` puts the Apple sheet up next attempt. Only with an
                // identity: no `userId` means an unreachable Keychain instead.
                state = .signedIn
            }

            progress = .failed(error.localizedDescription)
            return
        }

        // Nothing to prove: the erased row is gone and every credential it ever
        // minted went with it through `ON DELETE CASCADE`, so a value left in
        // the Keychain here would only be presented on requests belonging to
        // somebody who no longer exists.
        swapIdentity(to: UUID(), proving: nil)
        state = .localOnly

        for store in stores {
            await store.erase()
        }

        Self.logger.notice("erased the account and everything this device held")
        await onIdentityChange()
    }

    /// Records a failure that happened before there was a token to send, so
    /// nothing reached the server and nothing about the identity has changed.
    /// - Parameter message: the system's own words or this app's, never the
    ///   person's, which is what makes it safe to log as `.public`.
    public func reportSignInFailure(_ message: String) {
        Self.logger.notice("sign-in failed before the server: \(message, privacy: .public)")
        progress = .failed(message)
    }

    /// Records a failure from work the app started on its own, without showing
    /// it: a prefetched challenge is this app's own idea and has no button to
    /// sit under, unlike a refused sheet somebody tapped.
    /// - Parameter message: the transport's own words, never the person's,
    ///   which is what makes it safe to log as `.public`.
    public func noteUnaskedFailure(_ message: String) {
        Self.logger.notice("a speculative account call failed: \(message, privacy: .public)")
    }
}
