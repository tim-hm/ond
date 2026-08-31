import Foundation
@testable import OndKit
import os
import Testing

/// Signing in, signing out, and the identity swap either performs. Both
/// failure modes are silent in the field: keeping the id you signed out of
/// binds the install to that first Apple account forever — the server refuses
/// to rebind, by design — and ignoring the id a sign-in answered with writes
/// onto a row the server recreates empty, which no sign-in will find.
@MainActor
@Suite("Account")
struct AccountModelTests {
    /// Restoring on a second device, which is what signing in is for: the Apple
    /// account already has an identity, this install's is merged into it, and
    /// the id that comes back is the one the person's practice is filed under.
    @Test("The identity the server answers with is adopted, and everything is told")
    func adoptsTheReturnedIdentity() async throws {
        let identity = mintingStore(holding: anIdentity())
        let history = anIdentity()
        let told = OSAllocatedUnfairLock(initialState: 0)
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity, bindings: ["apple-a": history]),
            defaults: accountDefaults("adopts")
        ) {
            told.withLock { $0 += 1 }
        }

        await account.signIn(identityToken: "apple-a")

        #expect(identity.userId() == history)
        #expect(account.state == .signedIn)
        #expect(account.progress == .idle)
        #expect(told.withLock { $0 } == 1, "the watch and the restore both hold the old id")
    }

    /// A first sign-in — nobody held this Apple account — is answered with the
    /// caller's own id. The id is unchanged but the row is bound now: every
    /// request naming it is refused without the credential this response carried.
    /// The watch holds its own copy of the id, so it must be told even though its
    /// copy is still right — hence asserting the hand-over happened.
    @Test("A first sign-in keeps the identity it arrived with")
    func keepsTheCallersIdentityOnAFirstSignIn() async throws {
        let held = anIdentity()
        let identity = mintingStore(holding: held)
        let told = OSAllocatedUnfairLock(initialState: 0)
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("first-sign-in")
        ) {
            told.withLock { $0 += 1 }
        }

        await account.signIn(identityToken: "apple-a")

        #expect(identity.userId() == held)
        #expect(account.state == .signedIn)
        #expect(
            told.withLock { $0 } == 1,
            "the watch carries this id too, and is refused every request without the credential"
        )
        #expect(identity.sessionCredential() != nil)
    }

    /// One installation, two people, and the sign-out in between is the only
    /// thing standing between them. The second account already has an identity,
    /// so nothing here is refused — the caller's row is merged into theirs and
    /// deleted, and what it takes with it is the first account's binding.
    @Test("Sign in as one account, sign out, and sign in as another lands on their history")
    func signingOutKeepsTheFirstAccountsHistoryOutOfTheSecond() async throws {
        let identity = mintingStore(holding: anIdentity())
        let theirs = anIdentity()
        let accounts = FakeAccounts(identity: identity, bindings: ["apple-b": theirs])
        let account = try accountModel(
            identity: identity,
            accounts: accounts,
            defaults: accountDefaults("second-account")
        )

        await account.signIn(identityToken: "apple-a")
        let first = identity.userId()
        await account.signOut()
        await account.signIn(identityToken: "apple-b")

        #expect(account.progress == .idle)
        #expect(account.state == .signedIn)
        #expect(identity.userId() == theirs)
        #expect(
            accounts.boundAccounts["apple-a"] == first,
            "the fresh identity is what is merged away, rather than the first account's"
        )
    }

    /// The same flow where the second account is new, which is where the server
    /// refuses rather than merges: `claim` will not rebind a row that already
    /// holds an Apple account, so an install that kept the id it signed out of
    /// can never sign in as anybody else again.
    @Test("Sign in, sign out, and sign in as a new account binds rather than being refused")
    func signingOutFreesTheInstallForANewAccount() async throws {
        let identity = mintingStore(holding: anIdentity())
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("new-account")
        )

        await account.signIn(identityToken: "apple-a")
        await account.signOut()
        await account.signIn(identityToken: "apple-b")

        #expect(account.progress == .idle)
        #expect(account.state == .signedIn)
    }

    @Test("Signing out mints an identity that is nobody's history")
    func signingOutMintsAFreshIdentity() async throws {
        let identity = mintingStore(holding: anIdentity())
        let told = OSAllocatedUnfairLock(initialState: 0)
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("sign-out")
        ) {
            told.withLock { $0 += 1 }
        }

        await account.signIn(identityToken: "apple-a")
        let bound = identity.userId()
        await account.signOut()

        #expect(account.state == .localOnly)
        #expect(identity.userId() != nil)
        #expect(identity.userId() != bound)
        #expect(
            told.withLock { $0 } == 2,
            "once for the sign-in that bound this id, once for the sign-out that unbound it"
        )
        #expect(
            identity.sessionCredential() == nil,
            "the device keeps nothing that could prove the account it has left"
        )
    }

    /// The one way an honest client reaches `FAILED_PRECONDITION`: the Keychain
    /// identity outlives a reinstall and `UserDefaults` does not, so the app
    /// offers a sign-in believing it is the first. The refusal is the server
    /// telling it otherwise, and recording that is what puts the sign-out — the
    /// only way back — in front of the person.
    @Test("A refusal reveals a binding this install had forgotten, and is recoverable")
    func recordsABindingItHadForgotten() async throws {
        let held = anIdentity()
        let identity = mintingStore(holding: held)
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity, bindings: ["apple-a": held]),
            defaults: accountDefaults("forgotten")
        )

        await account.signIn(identityToken: "apple-b")

        #expect(account.state == .signedIn)
        #expect(account.progress.reason != nil)

        await account.signOut()
        await account.signIn(identityToken: "apple-b")

        #expect(account.progress == .idle)
        #expect(account.state == .signedIn)
    }

    /// The id Settings shows has to be the id requests are stamped with, at every
    /// swap. A row showing a retired identity is worse than no row: it is the
    /// number somebody quotes to support to be found, and it names either nothing
    /// or, after a merging sign-in, the wrong row.
    @Test("The published identifier follows every swap")
    func publishesTheLiveIdentity() async throws {
        let identity = mintingStore(holding: anIdentity())
        let history = anIdentity()
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity, bindings: ["apple-a": history]),
            defaults: accountDefaults("published-identity")
        )

        #expect(account.userId == identity.userId(), "there is an id before anything happens")

        await account.signIn(identityToken: "apple-a")

        #expect(account.userId == history)

        await account.signOut()

        #expect(account.userId == identity.userId())
        #expect(account.userId != history, "the merged-into identity is not this install's")
    }

    /// What Settings offers for copying identifies the record without authorising
    /// anything. Possession of the id is the whole claim to the account, so
    /// copying it under "Support ID" invited mailing a bearer credential to a
    /// stranger. The prefix still finds the one row server-side, and lowercase
    /// matters: the server stores and logs the lowercase form.
    @Test("The support reference is a prefix of the identity, never the identity")
    func offersAReferenceRatherThanTheIdentity() throws {
        let identity = mintingStore(holding: anIdentity())
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("support-reference")
        )
        let id = try #require(account.userId)
        let reference = try #require(account.supportReference)

        #expect(
            reference.count == 13,
            "twelve hex characters and the hyphen between the first two groups"
        )
        #expect(
            id.uuidString.lowercased().hasPrefix(reference),
            "a LIKE prefix on the server's lowercase form has to find the row"
        )
    }

    /// The strand the merge tombstone creates: a phone whose sign-in merged its id away
    /// but whose response was lost keeps presenting the dead id, and the server refuses
    /// everything under it — including the retry that used to self-heal by recreating
    /// the row. The way out is the documented one, automated: mint a fresh identity and
    /// sign in on that, which hands back the account's identity.
    @Test("A sign-in stranded on a merged-away identity recovers under a fresh one")
    func strandedSignInRecovers() async throws {
        let dead = anIdentity()
        let account = anIdentity()
        let store = mintingStore(holding: dead)
        let model = try accountModel(
            identity: store,
            accounts: TombstoningAccounts(
                identity: store,
                bindings: ["token-apple": account],
                dead: dead
            ),
            defaults: accountDefaults("stranded-recovers")
        )

        let nonce = try await model.beginAppleAuthorization(for: .signIn)
        await model.signIn(identityToken: "token-apple")

        #expect(nonce.nonce == "nonce-1")
        #expect(model.state == .signedIn)
        #expect(model.userId == account, "the Apple account hands back the identity it already had")
        #expect(model.progress == .idle)
    }

    /// Token rejection happens after challenge prefetch, so it cannot trigger
    /// the stranded-id recovery or cost a healthy anonymous identity.
    @Test("A rejected token does not cost the identity it was presented under")
    func rejectedTokenKeepsTheIdentity() async throws {
        let mine = anIdentity()
        let store = mintingStore(holding: mine)
        let model = try accountModel(
            identity: store,
            accounts: TokenRejectingAccounts(),
            defaults: accountDefaults("rejected-token")
        )

        await model.signIn(identityToken: "token-expired")

        #expect(model.state == .localOnly)
        #expect(model.userId == mine, "a healthy anonymous identity survives a bad token")
        #expect(model.progress.reason != nil)
    }

    @Test("Apple authorization preserves the action's purpose")
    func authorizationPurposesStayDistinct() async throws {
        let identity = mintingStore(holding: anIdentity())
        let accounts = FakeAccounts(identity: identity)
        let model = try accountModel(
            identity: identity,
            accounts: accounts,
            defaults: accountDefaults("authorization-purpose")
        )

        _ = try await model.beginAppleAuthorization(for: .signIn)
        _ = try await model.beginAppleAuthorization(for: .deleteAccount)

        #expect(accounts.authorizationPurposes == [.signIn, .deleteAccount])
    }

    @Test("A prefetched Apple challenge is retained only before its expiry")
    func challengeValidityUsesTheServerExpiry() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let challenge = AppleAuthorizationChallenge(nonce: "nonce", expiresAt: expiry)

        #expect(challenge.isValid(at: expiry.addingTimeInterval(-0.001)))
        #expect(
            challenge.appleNonce
                == "78377b525757b494427f89014f97d79928f3938d14eb51e20fb5dec9834eb304"
        )
        #expect(!challenge.isValid(at: expiry))
        #expect(!challenge.isValid(at: expiry.addingTimeInterval(1)))
        #expect(
            !AppleAuthorizationChallenge(nonce: "", expiresAt: .distantFuture).isValid(),
            "an expiry cannot make a missing nonce usable"
        )
    }

    /// Local-only is where everybody starts and most people stay, and nothing
    /// about it is a failure state.
    @Test("An install that has never signed in is local only")
    func startsLocalOnly() throws {
        let identity = mintingStore()
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("fresh")
        )

        #expect(account.state == .localOnly)
        #expect(account.progress == .idle)
    }
}
