import Foundation
@testable import OndKit
import os
import Testing

/// What a sign-in hands back besides an identity, and what a sign-out does
/// with it. Its own suite because the failure modes are not the identity's:
/// adopting the id but dropping the credential means every later request is
/// refused with nothing on screen to say why; signing out but keeping it
/// leaves a live claim on a phone somebody may be handing on.
@MainActor
@Suite("Session credential")
struct AccountCredentialTests {
    /// The credential is the whole of what this install can prove from now on, and
    /// losing it is indistinguishable from never having signed in — the server has no
    /// way to hand one back. Asserted through the store rather than the model because
    /// that is where the interceptor reads it from: a model that kept it in a property
    /// of its own would satisfy every other test here and send no header at all.
    @Test("A sign-in keeps the credential that identity now has to prove")
    func keepsTheCredentialASignInReturns() async throws {
        let identity = mintingStore(holding: anIdentity())
        let account = try accountModel(
            identity: identity,
            accounts: FakeAccounts(identity: identity),
            defaults: accountDefaults("credential")
        )

        #expect(identity.sessionCredential() == nil, "nothing to prove before signing in")

        await account.signIn(identityToken: "apple-a")

        #expect(identity.sessionCredential() != nil)
    }

    /// Signing out revokes on the server *and* forgets locally. Revoking alone
    /// leaves the device presenting a value every request is refused for;
    /// forgetting alone leaves a live credential on a phone being handed on.
    /// The fake revokes whatever is currently presented, so this also pins that
    /// the call goes out *before* the credential is cleared.
    @Test("Signing out revokes the credential this install was presenting")
    func revokesTheCredentialOnTheWayOut() async throws {
        let identity = mintingStore(holding: anIdentity())
        let accounts = FakeAccounts(identity: identity)
        let account = try accountModel(
            identity: identity,
            accounts: accounts,
            defaults: accountDefaults("revoke")
        )

        await account.signIn(identityToken: "apple-a")
        let presented = try #require(identity.sessionCredential())

        await account.signOut()

        #expect(accounts.revokedCredentials == [presented])
        #expect(identity.sessionCredential() == nil)
    }

    /// A sign-out with no signal still signs the person out. Refusing would
    /// leave somebody signed in to an account they have finished with, on a
    /// device they may be giving away, because a train went into a tunnel. What
    /// survives is one credential nobody holds any more, which deleting the
    /// account revokes along with everything else.
    @Test("A sign-out the server never heard still returns this install to local only")
    func signsOutWithoutTheServer() async throws {
        let identity = mintingStore(holding: anIdentity())
        let account = try accountModel(
            identity: identity,
            accounts: RefusingAccounts(identity: identity),
            defaults: accountDefaults("offline-sign-out")
        )

        await account.signIn(identityToken: "apple-a")
        let bound = identity.userId()

        await account.signOut()

        #expect(account.state == .localOnly)
        #expect(identity.userId() != bound)
        #expect(identity.sessionCredential() == nil)
        #expect(account.failure == nil, "nothing here is the person's problem to read")
    }
}
