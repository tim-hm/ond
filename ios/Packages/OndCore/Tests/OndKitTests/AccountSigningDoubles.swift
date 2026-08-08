import Foundation
@testable import OndKit
import os
import Testing

/// The store the phone composes, over storage that never touches a Keychain.
func mintingStore(holding id: UUID? = nil) -> KeychainUserIdentityStore {
    KeychainUserIdentityStore(storage: FakeStorage(holding: id))
}

/// `AccountService` with the three rules that decide what signing in and out
/// do, and nothing else.
///
/// The caller is read from the identity store on every call, exactly as
/// `IdentityInterceptor` reads it to stamp the headers — which is what makes
/// this able to catch a client that signed out without changing its id, or one
/// that revoked a credential it was no longer presenting, since the server's
/// answer is a fact about *what the request carried*.
///
/// An identity token stands in for the Apple account it names, because `sub` is
/// the only claim the server acts on.
final class FakeAccounts: AccountSyncing {
    /// Apple account → the identity holding it, which is `users.apple_user_id`
    /// read the way a sign-in reads it.
    private let bindings: OSAllocatedUnfairLock<[String: UUID]>
    /// Every credential a sign-out revoked, so a test can see that it was the
    /// one the install was actually presenting.
    private let revoked = OSAllocatedUnfairLock<[String]>(initialState: [])
    private let identity: any UserIdentityStore

    init(identity: any UserIdentityStore, bindings: [String: UUID] = [:]) {
        self.identity = identity
        self.bindings = OSAllocatedUnfairLock(initialState: bindings)
    }

    /// Which identity each Apple account is filed under, after whatever has
    /// happened to them.
    var boundAccounts: [String: UUID] {
        bindings.withLock { $0 }
    }

    var revokedCredentials: [String] {
        revoked.withLock { $0 }
    }

    /// Unreachable from the suites this serves. What a deletion does is pinned
    /// in `AccountDeletionTests`, over the real stores rather than a double.
    func delete(identityToken _: String?) async throws {
        throw AccountRepositoryError.transport("not what these suites are about")
    }

    /// Revokes whatever the caller is currently presenting, which is what the
    /// server does with the header the interceptor puts on the request. An
    /// anonymous caller presents nothing and is answered `OK` having had nothing
    /// to revoke.
    func signOut() async throws {
        guard let presented = identity.sessionCredential() else { return }
        revoked.withLock { $0.append(presented) }
    }

    func signIn(identityToken: String) async throws -> SignedInIdentity {
        guard let caller = identity.userId() else {
            throw AccountRepositoryError.transport("no identity to bind")
        }

        let adopted = try bindings.withLock { held -> UUID in
            // Somebody's row holds this Apple account. It is that person's real
            // history, so the caller is merged into it and *deleted* — taking
            // whatever Apple account the caller was bound to with it, which is
            // the half of this that never surfaces as an error.
            if let holder = held[identityToken] {
                if holder != caller {
                    held = held.filter { $0.value != caller }
                }
                return holder
            }

            // `claim` refuses a caller already bound to another account, because
            // the column it would overwrite is the only record of the first one.
            if held.values.contains(caller) {
                throw AccountRepositoryError.boundElsewhere
            }

            held[identityToken] = caller
            return caller
        }

        // A credential per sign-in, as the server mints one, and distinct per
        // call so a test can tell which of two the install is holding.
        return SignedInIdentity(
            userId: adopted,
            sessionCredential: "credential-for-\(adopted)-\(identityToken)"
        )
    }
}

/// `FakeAccounts` with the radio off: it binds as usual and cannot revoke.
///
/// Wraps the real double rather than reimplementing it, so the sign-in half
/// stays the one every other test is driven through — the case under test is a
/// person on a train, not a different server.
final class RefusingAccounts: AccountSyncing {
    private let real: FakeAccounts

    init(identity: any UserIdentityStore) {
        real = FakeAccounts(identity: identity)
    }

    func signIn(identityToken: String) async throws -> SignedInIdentity {
        try await real.signIn(identityToken: identityToken)
    }

    func signOut() async throws {
        throw AccountRepositoryError.transport("no route to the server")
    }

    func delete(identityToken: String?) async throws {
        try await real.delete(identityToken: identityToken)
    }
}

/// A `UserDefaults` nothing else in the process shares.
///
/// `AccountModel` mirrors `state` into one, so two suites sharing a suite name
/// would read each other's answer to "has this install signed in" — and the
/// bug that hides is the one `signIn` exists to repair.
func accountDefaults(_ name: String) throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "account-tests.\(name).\(UUID().uuidString)"))
}

/// The model over the doubles above.
///
/// The store list is empty on purpose: what a deletion empties is
/// `AccountDeletionTests`, and signing in or out touches none of it.
@MainActor
func accountModel(
    identity: any UserIdentityStore,
    accounts: any AccountSyncing,
    defaults: UserDefaults,
    onIdentityChange: @escaping @MainActor () async -> Void = {}
) -> AccountModel {
    AccountModel(
        identity: identity,
        accounts: accounts,
        stores: [],
        defaults: defaults,
        onIdentityChange: onIdentityChange
    )
}
