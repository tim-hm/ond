import Foundation
import OndAPI

public enum AccountRepositoryError: LocalizedError, Equatable {
    /// The RPC failed on something a later attempt may not hit — no network, a
    /// server that is down, Apple's signing keys out of reach.
    case transport(String)

    /// The server would not act on the credential: not a token it can verify,
    /// issued for another app, expired, absent where one was required, or
    /// proving a different Apple account than the identity is bound to.
    /// Retrying the same one changes nothing; asking Apple for a fresh one
    /// might, which is what the wording has to leave room for.
    case rejected(String)

    /// This installation's identity is already bound to a *different* Apple
    /// account, and the server refuses to rebind it — `users.apple_user_id` is
    /// the only record of the first account, so a rebind would strand that
    /// history with nothing left pointing at it.
    ///
    /// Reachable by an honest client in exactly one way: an install whose
    /// Keychain identity outlived the app's own record of having signed in, so
    /// the app offered a sign-in it believed was the first. Signing out mints a
    /// fresh identity, which is the way back.
    case boundElsewhere

    /// The response parsed but named an identity this app cannot use. Distinct
    /// from `.transport` because retrying will not help: the client and server
    /// contracts have diverged.
    case malformedResponse(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    public var errorDescription: String? {
        switch self {
        case let .transport(message): "the request failed: \(message)"
        case let .rejected(message): "the Apple credential was refused: \(message)"
        case .boundElsewhere: "this device is already signed in to another Apple ID"
        case let .malformedResponse(message): "the response could not be read: \(message)"
        }
    }
}

/// What a sign-in hands back: the identity to carry from now on, and the
/// credential that proves it.
///
/// Both, because a client that took only one of them is broken in a way it
/// cannot detect. The id is not always the caller's own — an Apple account that
/// already had an identity means that one is the person's real history, so this
/// install's is merged into it and the id comes back changed — and from the
/// moment that identity is bound, the server refuses every request on it that
/// cannot present the credential.
public struct SignedInIdentity: Sendable, Equatable {
    /// The identity to send in every request from now on. Anything that keeps
    /// using the old one writes onto a row the server recreates empty — see
    /// `UserIdentityStore.adopt`.
    public let userId: UUID

    /// What proves it. Issued once and never handed back: an install that loses
    /// this signs in again under a fresh anonymous id, which is the same path a
    /// new phone takes and returns the same identity.
    public let sessionCredential: String

    public init(userId: UUID, sessionCredential: String) {
        self.userId = userId
        self.sessionCredential = sessionCredential
    }
}

/// Attaches an Apple account to this install's identity, answers with the
/// identity to carry from then on, and takes it back again.
public protocol AccountSyncing: Sendable {
    /// - Parameter identityToken: the `identityToken` from
    ///   `ASAuthorizationAppleIDCredential`, verbatim. A JWT Apple signed, which
    ///   is what the server checks — rather than the plain `user` string beside
    ///   it in the same credential, which is a value a modified client can type.
    /// - Returns: the identity to carry, and what proves it.
    func signIn(identityToken: String) async throws -> SignedInIdentity

    /// Revokes the credential this install is currently presenting, and nothing
    /// else.
    ///
    /// The identity survives, still bound to its Apple account, with all of its
    /// history — signing out is a person handing a device on or switching
    /// accounts, not asking to be forgotten. Only the credential sent with this
    /// request is revoked, so somebody signed in on a second device stays signed
    /// in there.
    ///
    /// Answers nothing, and an install that has never signed in may call it: the
    /// server has nothing to revoke for such a caller and says `OK`, which is
    /// what lets a client clear its own state without first working out whether
    /// the server agrees it had any.
    func signOut() async throws

    /// Erases the calling identity and everything the server holds under it.
    ///
    /// Answers nothing, which is the shape of the contract: the caller has to
    /// mint a fresh identity itself the moment this returns, because the server
    /// has no id left to hand back and no memory of the one that just called.
    ///
    /// - Parameter identityToken: a fresh `identityToken` when this install is
    ///   signed in with Apple, and nil when it is not. The server requires one
    ///   exactly when the identity carries an `apple_user_id`: this is the only
    ///   irreversible operation in the API, and possession of an anonymous id is
    ///   not a credential it will weigh against a signed-in one. A `.rejected`
    ///   answer to a nil token is a bound install that had forgotten it was one.
    func delete(identityToken: String?) async throws
}

/// The only type that touches the generated account types, mirroring
/// `ProfileRepository`.
public struct AccountRepository: AccountSyncing {
    private let client: Ond_V1_AccountServiceClient

    public init(baseURL: URL, identity: any UserIdentityStore) {
        client = OndClients.accountService(
            baseURL: baseURL,
            userId: identity.userId,
            sessionCredential: identity.sessionCredential
        )
    }

    public func signIn(identityToken: String) async throws -> SignedInIdentity {
        var request = Ond_V1_SignInWithAppleRequest()
        request.identityToken = identityToken

        let response = await client.signInWithApple(request: request)

        guard let message = response.message else {
            let reason = response.error?.localizedDescription ?? "the server sent no message"
            // Switched on here rather than in a helper, because the two named
            // statuses are the only place this repository can name a Connect
            // `Code` at all: Connect is OndAPI's dependency and not this
            // target's, so the type is usable through inference and unnameable
            // in a signature.
            switch response.code {
            case .unauthenticated: throw AccountRepositoryError.rejected(reason)
            case .failedPrecondition: throw AccountRepositoryError.boundElsewhere
            default: throw AccountRepositoryError.transport(reason)
            }
        }

        guard let adopted = UUID(uuidString: message.userID) else {
            throw AccountRepositoryError.malformedResponse(
                "`user_id` is not a UUID: `\(message.userID)`"
            )
        }

        // Refused rather than stored, because an install that adopted this
        // identity with nothing to prove it would be answered `UNAUTHENTICATED`
        // on every request from here on, with no route back but a reinstall. A
        // server old enough not to send one is exactly that case.
        guard !message.sessionCredential.isEmpty else {
            throw AccountRepositoryError.malformedResponse(
                "the sign-in returned no session credential"
            )
        }

        return SignedInIdentity(
            userId: adopted,
            sessionCredential: message.sessionCredential
        )
    }

    /// The one call whose credential is the subject rather than the means: the
    /// interceptor puts it on the request, and the server revokes precisely
    /// what it was shown.
    public func signOut() async throws {
        let response = await client.signOut(request: Ond_V1_SignOutRequest())

        guard response.message != nil else {
            let reason = response.error?.localizedDescription ?? "the server sent no message"
            throw AccountRepositoryError.transport(reason)
        }
    }

    /// Three outcomes, for the same reason the sign-in has three: an erasure now
    /// carries a credential, so the server can refuse one.
    ///
    /// `UNAUTHENTICATED` is a bound identity that presented nothing —
    /// reachable by an honest client whose record of having signed in did not
    /// survive a reinstall — and `PERMISSION_DENIED` is a real Apple credential
    /// for somebody else's account. Both are `.rejected`, because the answer to
    /// each is the same one: sign in as the account being deleted. Anything else
    /// is a request that did not arrive.
    public func delete(identityToken: String?) async throws {
        var request = Ond_V1_DeleteAccountRequest()
        request.identityToken = identityToken ?? ""

        let response = await client.deleteAccount(request: request)

        guard response.message != nil else {
            let reason = response.error?.localizedDescription ?? "the server sent no message"

            switch response.code {
            case .unauthenticated, .permissionDenied: throw AccountRepositoryError.rejected(reason)
            default: throw AccountRepositoryError.transport(reason)
            }
        }
    }
}
