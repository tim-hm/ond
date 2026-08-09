import Foundation
@testable import OndKit
import os
import Testing

/// Signing in, signing out, and the identity swap either performs.
///
/// Two of this issue's three seams are here, and both are silent in the field.
/// An install that keeps the id it signed out of is bound to that first Apple
/// account forever — the server refuses to rebind, by design, and there is no
/// way back that does not involve reinstalling. An install that ignores the id a
/// sign-in answered with writes onto a row the server recreates empty, which no
/// later sign-in will ever find.
@MainActor
@Suite("Account")
struct AccountModelTests {
    /// Restoring on a second device, which is what signing in is for: the Apple
    /// account already has an identity, this install's is merged into it, and
    /// the id that comes back is the one the person's practice is filed under.
    @Test("The identity the server answers with is adopted, and everything is told")
    func adoptsTheReturnedIdentity() async throws {
        let identity = mintingStore(holding: UUID())
        let history = UUID()
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
        #expect(account.failure == nil)
        #expect(told.withLock { $0 } == 1, "the watch and the restore both hold the old id")
    }

    /// A first sign-in — nobody held this Apple account — is answered with the
    /// caller's own id.
    ///
    /// The id is unchanged and everything about what it is worth is not: the row
    /// is bound now, so every request naming it is refused without the
    /// credential this response carried. The watch holds its own copy of that id
    /// and syncs what was breathed on the wrist, so it has to be told even
    /// though the id it holds is still right — which is why this asserts the
    /// hand-over happened rather than that it did not.
    @Test("A first sign-in keeps the identity it arrived with")
    func keepsTheCallersIdentityOnAFirstSignIn() async throws {
        let held = UUID()
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
        let identity = mintingStore(holding: UUID())
        let theirs = UUID()
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

        #expect(account.failure == nil)
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
        let identity = mintingStore(holding: UUID())
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("new-account")
        )

        await account.signIn(identityToken: "apple-a")
        await account.signOut()
        await account.signIn(identityToken: "apple-b")

        #expect(account.failure == nil)
        #expect(account.state == .signedIn)
    }

    @Test("Signing out mints an identity that is nobody's history")
    func signingOutMintsAFreshIdentity() async throws {
        let identity = mintingStore(holding: UUID())
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
        let held = UUID()
        let identity = mintingStore(holding: held)
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity, bindings: ["apple-a": held]),
            defaults: accountDefaults("forgotten")
        )

        await account.signIn(identityToken: "apple-b")

        #expect(account.state == .signedIn)
        #expect(account.failure != nil)

        await account.signOut()
        await account.signIn(identityToken: "apple-b")

        #expect(account.failure == nil)
        #expect(account.state == .signedIn)
    }

    /// The id Settings shows has to be the id the requests are stamped with, at
    /// every point where the two could part company — which is every swap.
    ///
    /// A row still showing a retired identity is worse than no row: it is a
    /// number somebody quotes to support in order to be found, and it names
    /// either nothing at all or, after a sign-in that merged, the row they were
    /// folded into rather than the one they can still be asked about.
    @Test("The published identifier follows every swap")
    func publishesTheLiveIdentity() async throws {
        let identity = mintingStore(holding: UUID())
        let history = UUID()
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

    /// What Settings offers for copying identifies the record without
    /// authorising anything.
    ///
    /// Possession of the id is the whole claim to the account — reading it,
    /// rewriting it, spending its allowance, erasing it — so a row that copied
    /// the id itself to the pasteboard under the words "Support ID" was inviting
    /// somebody to mail a bearer credential to a stranger. The prefix still
    /// finds the one row server-side, which is what the label always promised,
    /// and the case matters because the form the server stores and logs is
    /// lowercase: a reference that did not match would find nothing.
    @Test("The support reference is a prefix of the identity, never the identity")
    func offersAReferenceRatherThanTheIdentity() throws {
        let identity = mintingStore(holding: UUID())
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

    /// Local-only is where everybody starts and most people stay, and nothing
    /// about it is a failure state.
    /// The strand the merge tombstone creates: a phone whose sign-in merged its
    /// id away but whose response was lost keeps presenting the dead id, and
    /// the server refuses everything under it — including the retry that used
    /// to self-heal by recreating the row. The way out is the documented one,
    /// automated: mint a fresh identity and sign in on that, which hands back
    /// the account's identity.
    @Test("A sign-in stranded on a merged-away identity recovers under a fresh one")
    func strandedSignInRecovers() async throws {
        let dead = UUID()
        let account = UUID()
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

        await model.signIn(identityToken: "token-apple")

        #expect(model.state == .signedIn)
        #expect(model.userId == account, "the Apple account hands back the identity it already had")
        #expect(model.failure == nil)
    }

    /// The retry must decide by outcome, because the server's refusal of a dead
    /// id and Apple's refusal of a bad token arrive as the same error. A bad
    /// token fails under the fresh id too — and the identity the person has
    /// been practising under must come back, not be abandoned to the retry.
    @Test("A rejected token does not cost the identity it was presented under")
    func rejectedTokenKeepsTheIdentity() async throws {
        let mine = UUID()
        let store = mintingStore(holding: mine)
        let model = try accountModel(
            identity: store,
            accounts: TokenRejectingAccounts(),
            defaults: accountDefaults("rejected-token")
        )

        await model.signIn(identityToken: "token-expired")

        #expect(model.state == .localOnly)
        #expect(model.userId == mine, "a healthy anonymous identity survives a bad token")
        #expect(model.failure != nil)
    }

    @Test("An install that has never signed in is local only")
    func startsLocalOnly() throws {
        let identity = mintingStore()
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("fresh")
        )

        #expect(account.state == .localOnly)
        #expect(account.failure == nil)
    }
}
