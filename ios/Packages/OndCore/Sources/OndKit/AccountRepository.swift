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

/// Attaches an Apple account to this install's identity, and answers with the
/// identity to carry from then on.
///
/// The returned id is the whole point of the call rather than a confirmation of
/// the one that made it: an Apple account that already had an identity means
/// that one is the person's real history, so this install's is merged into it
/// and the id comes back changed. Anything that keeps using the old one writes
/// onto a row the server recreates empty — see `UserIdentityStore.adopt`.
public protocol AccountSyncing: Sendable {
    /// - Parameter identityToken: the `identityToken` from
    ///   `ASAuthorizationAppleIDCredential`, verbatim. A JWT Apple signed, which
    ///   is what the server checks — rather than the plain `user` string beside
    ///   it in the same credential, which is a value a modified client can type.
    /// - Returns: the identity to send in every request from now on.
    func signIn(identityToken: String) async throws -> UUID

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
        client = OndClients.accountService(baseURL: baseURL, userId: identity.userId)
    }

    public func signIn(identityToken: String) async throws -> UUID {
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

        return adopted
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
