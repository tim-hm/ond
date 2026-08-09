import Foundation
import Observation
import os

/// Signing in, signing out, deleting the account, and the identity swap all
/// three of them perform.
///
/// The swap is the reason this is a model rather than three lines in a view.
/// Sign in and the server may answer with an identity *older* than the caller's,
/// having merged this install's history into it; sign out and this install must
/// stop using the identity it just bound, or the next person to sign in here
/// either cannot, or inherits a stranger's practice — `signOut` has the full
/// account of that. Delete, and the id names nothing at all, while the server
/// would recreate it the moment anything asked. All three are the same rule: the
/// client is the authority on which id is live, so every path that changes it
/// changes it completely, and every one of them ends with everything holding a
/// copy being told.
@MainActor
@Observable
public final class AccountModel {
    private static let logger = Logger(category: "account")

    /// Whether this install has bound an Apple account.
    ///
    /// Kept in `UserDefaults` rather than the Keychain, which means a reinstall
    /// reads back `.localOnly` while the surviving Keychain identity may still
    /// be bound. That install's next sign-in is answered with
    /// `boundElsewhere` if it names a different Apple account, and `signIn`
    /// below records what the server just revealed — so the state repairs
    /// itself, and the sign-out that is the way back becomes reachable.
    public private(set) var state: AccountState {
        didSet { defaults.set(state == .signedIn, forKey: Self.signedInKey) }
    }

    /// The anonymous identity this install's work is filed under.
    ///
    /// Published because it is the only handle a local-only person has. They
    /// have no name, no email and no account to quote, so when they write in
    /// asking what is held about them, this id is the entire answer to "which
    /// record is yours". Nil only where the Keychain could not be read, which is
    /// the one case with nothing honest to show.
    ///
    /// Mirrored here rather than read back through `identity` on demand: a
    /// computed property reaching into a store registers no dependency with
    /// Observation, so the screen would go on showing an id that a deletion had
    /// already retired — correct only by the coincidence that `state` changes in
    /// the same breath, and wrong the first time that stops being true.
    ///
    /// Reading it in the initialiser is what brings the identity into existence
    /// on a first launch, because the phone's store mints on the first ask.
    /// Building this model is therefore a Keychain round-trip; it was already
    /// one on the first request out, and this only moves it a moment earlier.
    public private(set) var userId: UUID?

    /// What this install quotes when its owner writes in, and the only form of
    /// the identity that ever leaves the device by hand.
    ///
    /// The first two groups of the id — twelve hex characters, lowercased —
    /// which is the derivation `obs::record_user_id` records on every request
    /// line server-side. **The two definitions must match**: a person quoting
    /// theirs and an operator grepping the log have to arrive at one string, and
    /// that string still finds the one row with a `LIKE` prefix.
    ///
    /// Never the whole id, which is the point. Possession of that is the whole
    /// claim to the account — reading and rewriting the profile, spending the
    /// assistant's allowance, and erasing the lot irreversibly — so a row
    /// offering it for copying was moving a bearer credential into a mail
    /// provider, a screenshot and a clipboard manager, and telling the person
    /// that is what it is for. A prefix identifies without authorising.
    ///
    /// Nil exactly when `userId` is: a Keychain that could not be read has
    /// nothing honest to show.
    public var supportReference: String? {
        userId.map { String($0.uuidString.prefix(Self.supportReferenceLength)).lowercased() }
    }

    /// What went wrong, for the one screen that asked. Cleared by the next
    /// attempt, since a stale reason beside a fresh button is worse than none.
    public private(set) var failure: String?

    /// Whether a sign-in is on the wire. The RPC reaches Apple's key endpoint
    /// through the server on a cold key cache, so this is long enough to need
    /// saying.
    public private(set) var isWorking = false

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
    ///   root rather than discovered, because there is no way to discover one
    ///   and a store left off the list is a deletion that quietly is not one.
    /// - Parameter onIdentityChange: run after the identity has actually
    ///   changed, to tell everything holding a copy of it — the watch, which
    ///   carries its own, and the journey, whose restore has already run under
    ///   the old one. A closure because both of those are composed above this
    ///   package, and one because they are one event.
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

    /// Makes `id` the identity from now on, and republishes it.
    ///
    /// Every swap below goes through here rather than calling `adopt` directly,
    /// because `userId` is a second copy of something the store already holds
    /// and a path that forgot to update it is a screen showing an identity the
    /// server has since merged away or erased.
    ///
    /// - Parameter credential: what proves the new identity, or nil where there
    ///   is nothing to prove — a fresh anonymous id, which a sign-out and a
    ///   deletion both mint.
    /// - Returns: what `UserIdentityStore.adopt` returns — whether this actually
    ///   changed the identity, and therefore whether anything else holding a
    ///   copy needs telling.
    ///
    /// The credential is written first and the id second, which is the order
    /// `UserIdentityStore.adopt(sessionCredential:)` explains: the interceptor
    /// reads the two separately, and the pair caught the other way round is a
    /// bound id presenting a credential the server has already replaced.
    @discardableResult
    private func swapIdentity(to id: UUID, proving credential: String?) -> Bool {
        identity.adopt(sessionCredential: credential)
        let changed = identity.adopt(id)
        userId = id
        return changed
    }

    /// Binds the Apple credential, adopts whatever identity comes back, and
    /// keeps the credential that identity now has to prove itself with.
    ///
    /// The adopt happens before this returns and before anything else is
    /// awaited, so no request can be stamped with the merged-away id after the
    /// server has deleted it — or with the bound one before this device can
    /// prove it.
    public func signIn(identityToken: String) async {
        failure = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await signIn(identityToken: identityToken, retryingStranded: true)
        } catch AccountRepositoryError.boundElsewhere {
            Self.logger.notice("this device is bound to a different Apple account")
            // The server has just told us something this install had forgotten:
            // it is bound, to somebody else's Apple account. Recording that is
            // what puts the sign-out in front of the person, which is the only
            // route from here to signing in as the account they offered.
            state = .signedIn
            failure = "This device is already signed in to a different Apple ID. "
                + "Sign out first, then sign in again."
        } catch {
            Self.logger.notice("sign-in failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
        }
    }

    /// The sign-in call and the adoption of everything it answers with.
    private func signIn(identityToken: String, retryingStranded: Bool) async throws {
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
        } catch AccountRepositoryError.rejected where retryingStranded {
            try await signInAgainAsStranded(identityToken: identityToken)
        }
    }

    /// One retry under a fresh identity, for an install stranded on an id the
    /// server refuses to resolve: a sign-in that merged the id away but lost
    /// the response, or a restore that kept a bound id without its credential.
    /// This is `identity::resolve`'s documented way out — mint a fresh
    /// anonymous id and sign in on that — and it converges because the Apple
    /// account hands back the identity it already had. Apple rejecting the
    /// *token* arrives as the same error, so the retry decides by outcome: a
    /// bad token fails under the fresh id too, and the stranded pair is
    /// restored before rethrowing — a healthy anonymous identity must not be
    /// abandoned over an expired token.
    private func signInAgainAsStranded(identityToken: String) async throws {
        let strandedId = identity.userId()
        let strandedCredential = identity.sessionCredential()

        Self.logger
            .notice("the server refused this identity; retrying the sign-in under a fresh one")
        swapIdentity(to: UUID(), proving: nil)

        do {
            try await signIn(identityToken: identityToken, retryingStranded: false)
        } catch {
            if let strandedId {
                swapIdentity(to: strandedId, proving: strandedCredential)
            }
            throw error
        }
    }

    /// Returns this install to local-only under a **fresh** anonymous identity.
    ///
    /// Minting is the point rather than a detail. An install that kept the id it
    /// just signed out of stays bound to that first Apple account, and the next
    /// sign-in as somebody else goes one of two ways, both bad. If that account
    /// is new, `bind_apple_account` refuses it — rebinding would drop the first
    /// account's only route back to its history — and nothing on either side can
    /// undo that short of reinstalling. If that account already has an identity,
    /// there is no refusal at all: the caller's row is merged into theirs and
    /// deleted, so the first person's practice is handed to the second and their
    /// binding goes with it.
    ///
    /// The id is minted here rather than asked of the store because `UUID()` is
    /// not knowledge about where an identity is kept, and because the store that
    /// must never invent one is the watch's.
    ///
    /// What stays behind is the practice already on this device: it is theirs,
    /// it is what the journey draws from with no signal at all, and the sync
    /// ledger has it acknowledged — so it is not re-sent, and signing in as
    /// somebody else does not donate this history to them.
    ///
    /// The server is told first, so the credential this device is about to
    /// forget is revoked rather than left live on a row somebody may be handing
    /// on with the phone. **Best effort, and deliberately so.** A person with no
    /// signal must still be able to sign out — refusing would leave them
    /// signed in to an account they have finished with, on a device they may be
    /// giving away — so a failed revocation is a log line and the local half
    /// proceeds. What survives it is one credential nobody holds any more, and
    /// deleting the account revokes it along with everything else.
    public func signOut() async {
        failure = nil

        do {
            try await accounts.signOut()
        } catch {
            Self.logger.notice(
                "the session credential was not revoked: \(error.localizedDescription, privacy: .public)"
            )
        }

        state = .localOnly

        if swapIdentity(to: UUID(), proving: nil) {
            await onIdentityChange()
        }
    }

    /// Erases the account on the server, then everything this device holds about
    /// the person, and starts them again under an identity nobody has ever seen.
    ///
    /// Offered whether or not this install has signed in, because signing in was
    /// never what created anything: an anonymous identity has a row, sessions, a
    /// controlled-pause history and possibly an entitlement from its first RPC.
    /// A "delete account" that only appeared once you had one would leave the
    /// majority of people with no way to erase what is held about them.
    ///
    /// The order below is the whole of the correctness, and each step is only
    /// safe after the one above it:
    ///
    /// 1. **The server first.** Nothing local is touched until the row is gone,
    ///    so a request that failed leaves a device that can simply ask again.
    ///    Erasing first would strand somebody offline with an empty app and a
    ///    server that still holds everything.
    /// 2. **A fresh identity next, before anything is awaited.** The old id
    ///    names nothing now, and `identity::resolve` upserts a row for any
    ///    well-formed id it is shown — so a single request that slipped out
    ///    under it would recreate the erased person as an empty stranger. This
    ///    is the rule signing out follows, for a sharper version of the same
    ///    reason.
    /// 3. **Then the local stores**, each of which answers for its own files,
    ///    keys and in-memory copies — and, in the schedules' case, for the
    ///    pending notifications iOS is holding on their behalf, which nothing
    ///    else could take back.
    /// 4. **Then everything holding a copy of the identity**, which is where the
    ///    watch is told — and told *after* the erasure rather than before, so
    ///    the context it is handed carries the fresh id and no personal best,
    ///    rather than the departing person's.
    ///
    /// What survives is the App Store subscription, which is not this app's to
    /// cancel. `SubscriptionStore.erase` re-derives it from `StoreKit` on the
    /// way past, and the confirmation that leads here says so plainly.
    ///
    /// - Parameter identityToken: a *fresh* `identityToken` for a signed-in
    ///   install, and nil for a local-only one. Undefaulted, because this is the
    ///   one irreversible operation in the API and a caller that omitted the
    ///   credential by forgetting rather than by deciding would find out as a
    ///   refusal in the field. The server decides which it needs from the row
    ///   rather than from this argument: `state` is kept in `UserDefaults` and a
    ///   reinstall reads it back as `.localOnly` while the surviving Keychain
    ///   identity is still bound, so a client that believes itself anonymous can
    ///   be wrong — and is answered with a refusal it can show rather than an
    ///   erasure it should not have had.
    public func deleteAccount(identityToken: String?) async {
        failure = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await accounts.delete(identityToken: identityToken)
        } catch {
            Self.logger.notice(
                "account deletion failed: \(error.localizedDescription, privacy: .public)"
            )

            if case .rejected? = error as? AccountRepositoryError, userId != nil {
                // The server has just told us what this install had forgotten:
                // it is signed in. `state` lives in `UserDefaults` and a
                // reinstall wipes it, while the Keychain identity — and its
                // binding — survive one by design, so every reinstalled
                // signed-in person arrives here believing they are local only.
                // Recording it is what puts the Apple sheet in front of them on
                // the next attempt; without it the deletion is refused the same
                // way forever, which is the thing the whole screen exists to
                // offer. `signIn` repairs the same state from the other
                // direction.
                //
                // Only when the request carried an identity, though: with no
                // `userId` the call went out without the header at all, and the
                // server refuses that the same way — but it is describing an
                // unreachable Keychain, not an Apple binding, and an Apple
                // sheet cannot repair it.
                state = .signedIn
            }

            failure = error.localizedDescription
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

    /// Records a failure that happened before there was a token to send — the
    /// system's own sheet failing, or a credential this app could not read.
    ///
    /// Separate from `signIn` because nothing reached the server, so there is no
    /// status to interpret and nothing about the identity has changed.
    ///
    /// - Parameter message: the system's own words or this app's, never the
    ///   person's, which is what makes it safe to log as `.public`.
    public func reportSignInFailure(_ message: String) {
        Self.logger.notice("sign-in failed before the server: \(message, privacy: .public)")
        failure = message
    }
}
