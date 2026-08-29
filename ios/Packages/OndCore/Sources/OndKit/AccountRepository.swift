import CryptoKit
import Foundation
import OndAPI

/// Why signing in, signing out or deleting failed, in the four shapes a caller
/// treats differently.
public enum AccountRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC failed on something a later attempt may not hit — no network, a
    /// server that is down, Apple's signing keys out of reach.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)

    /// The server would not act on the credential: not a token it can verify,
    /// issued for another app, expired, absent where one was required, or
    /// proving a different Apple account than the identity is bound to.
    /// Retrying the same one changes nothing; asking Apple for a fresh one
    /// might, which is what the wording has to leave room for.
    case rejected(String)

    /// This installation's identity is already bound to a *different* Apple
    /// account; `users.apple_user_id` is the only record of the first account,
    /// so a rebind would strand that history. Reachable honestly when the
    /// Keychain identity outlives the app's record of having signed in.
    /// Signing out mints a fresh identity, which is the way back.
    case boundElsewhere

    /// The response parsed but named an identity this app cannot use. Distinct
    /// from `.transport` because retrying will not help: the client and server
    /// contracts have diverged.
    case malformedResponse(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    /// A refusal says what to do rather than what the verifier said: the reason
    /// names a token, and the only move it leaves is to try the sheet again.
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case .rejected: "Apple couldn't confirm that sign-in. Try again."
        case .boundElsewhere:
            "This device is already signed in to a different Apple ID. "
                + "Sign out first, then sign in again."
        case .malformedResponse: "The server's answer arrived in a form the app couldn't read."
        }
    }

    /// What a log records — the transport's own words, kept off the screen.
    public var diagnostic: String {
        switch self {
        case let .transport(fault): fault.diagnostic
        case let .rejected(message): "the Apple credential was refused: \(message)"
        case .boundElsewhere: "this device is already signed in to another Apple ID"
        case let .malformedResponse(message): "the response could not be read: \(message)"
        }
    }
}

/// What a sign-in hands back: the identity to carry from now on, and the
/// credential that proves it. Both, because the id is not always the caller's
/// own — an Apple account with an existing identity merges this install's
/// into it — and once bound, the server refuses every request on it that
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

    /// Memberwise, made public: the server mints these, and a test double has
    /// to be able to as well.
    public init(userId: UUID, sessionCredential: String) {
        self.userId = userId
        self.sessionCredential = sessionCredential
    }
}

/// One server-issued Apple ceremony, including the instant a prefetched sign-in
/// must be discarded.
public struct AppleAuthorizationChallenge: Sendable, Equatable {
    /// The 256 random bits to hash into Apple's request.
    public let nonce: String
    /// The absolute server-issued expiry.
    public let expiresAt: Date

    public init(nonce: String, expiresAt: Date) {
        self.nonce = nonce
        self.expiresAt = expiresAt
    }

    /// The lowercase SHA-256 Apple signs into the identity token.
    public var appleNonce: String {
        SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Whether Apple can still be asked to sign this challenge.
    public func isValid(at date: Date = .now) -> Bool {
        !nonce.isEmpty && date < expiresAt
    }
}

/// The account action one server-issued Apple challenge may authorize.
public enum AppleAuthorizationPurpose: Sendable, Equatable {
    /// Bind or recover an Apple account.
    case signIn
    /// Permanently erase an Apple-bound account.
    case deleteAccount
}

/// Attaches an Apple account to this install's identity, answers with the
/// identity to carry from then on, and takes it back again.
public protocol AccountSyncing: Sendable {
    /// Starts a five-minute, caller-bound ceremony for one Apple account action.
    ///
    /// - Parameter purpose: the only action the resulting nonce may authorize.
    /// - Returns: 256 random bits to hash into Apple's authorization request.
    func beginAppleAuthorization(
        for purpose: AppleAuthorizationPurpose
    ) async throws -> AppleAuthorizationChallenge

    /// - Parameter identityToken: the `identityToken` from
    ///   `ASAuthorizationAppleIDCredential`, verbatim. A JWT Apple signed, which
    ///   is what the server checks — rather than the plain `user` string beside
    ///   it in the same credential, which is a value a modified client can type.
    /// - Returns: the identity to carry, and what proves it.
    func signIn(identityToken: String) async throws -> SignedInIdentity

    /// Revokes the credential this install is currently presenting, and nothing
    /// else: the identity survives, still bound, with its history, and a second
    /// device stays signed in. An install that never signed in may call it —
    /// the server says `OK` with nothing to revoke, so a client can clear its
    /// own state without asking whether the server agrees it had any.
    func signOut() async throws

    /// Erases the calling identity and everything the server holds under it.
    /// Answers nothing: the caller must mint a fresh identity on return.
    /// - Parameter identityToken: a fresh token when signed in with Apple, nil
    ///   otherwise; the server requires one exactly when the identity carries an
    ///   `apple_user_id`, and `.rejected` on a nil token is a forgotten binding.
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

    public func beginAppleAuthorization(
        for purpose: AppleAuthorizationPurpose
    ) async throws -> AppleAuthorizationChallenge {
        var request = Ond_V1_BeginAppleAuthorizationRequest()
        request.purpose = switch purpose {
        case .signIn: .signIn
        case .deleteAccount: .deleteAccount
        }

        let response = await client.beginAppleAuthorization(request: request)

        guard let message = response.message else {
            let reason = response.error.responseMessage
            switch response.code {
            case .unauthenticated: throw AccountRepositoryError.rejected(reason)
            default: throw AccountRepositoryError.transport(
                    TransportFault(outcome: response.transportOutcome, diagnostic: reason)
                )
            }
        }

        guard !message.nonce.isEmpty, message.hasExpiresAt else {
            throw AccountRepositoryError.malformedResponse(
                "the Apple authorization returned no nonce or expiry"
            )
        }

        let challenge = AppleAuthorizationChallenge(
            nonce: message.nonce,
            expiresAt: message.expiresAt.date
        )
        guard challenge.isValid() else {
            throw AccountRepositoryError.malformedResponse(
                "the Apple authorization was already expired"
            )
        }

        return challenge
    }

    public func signIn(identityToken: String) async throws -> SignedInIdentity {
        var request = Ond_V1_SignInWithAppleRequest()
        request.identityToken = identityToken

        let response = await client.signInWithApple(request: request)

        guard let message = response.message else {
            let reason = response.error.responseMessage
            // Switched on here rather than in a helper, because the two named
            // statuses are the only place this repository can name a Connect
            // `Code` at all: Connect is OndAPI's dependency and not this
            // target's, so the type is usable through inference and unnameable
            // in a signature.
            switch response.code {
            case .unauthenticated: throw AccountRepositoryError.rejected(reason)
            case .failedPrecondition: throw AccountRepositoryError.boundElsewhere
            default: throw AccountRepositoryError.transport(
                    TransportFault(outcome: response.transportOutcome, diagnostic: reason)
                )
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
            let reason = response.error.responseMessage
            throw AccountRepositoryError.transport(
                TransportFault(outcome: response.transportOutcome, diagnostic: reason)
            )
        }
    }

    /// `UNAUTHENTICATED` is a bound identity that presented nothing (a
    /// reinstall that forgot it signed in); `PERMISSION_DENIED` is a real Apple
    /// credential for somebody else's account. Both are `.rejected`, because
    /// the answer to each is the same: sign in as the account being deleted.
    /// Anything else is a request that did not arrive.
    public func delete(identityToken: String?) async throws {
        var request = Ond_V1_DeleteAccountRequest()
        request.identityToken = identityToken ?? ""

        let response = await client.deleteAccount(request: request)

        guard response.message != nil else {
            let reason = response.error.responseMessage

            switch response.code {
            case .unauthenticated, .permissionDenied: throw AccountRepositoryError.rejected(reason)
            default: throw AccountRepositoryError.transport(
                    TransportFault(outcome: response.transportOutcome, diagnostic: reason)
                )
            }
        }
    }
}
