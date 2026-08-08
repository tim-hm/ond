import AuthenticationServices
import UIKit

/// One fresh Sign in with Apple credential, asked for outside a button.
///
/// `SignInWithAppleButton` is the ordinary way in and is what the sign-in row
/// uses, but a deletion has no button left to hang a request on: by the time the
/// credential is needed the person has already confirmed, and the confirmation
/// dialog cannot host a view. This drives the same `ASAuthorizationController`
/// the SwiftUI button drives, wrapped so a `Task` can await either the token or
/// the reason there is not one.
///
/// One instance per request. The controller holds its delegate weakly, so the
/// caller's `await` is what keeps this alive for the round trip — which is also
/// why nothing here has to guard against a second concurrent request.
@MainActor
final class AppleIdentityRequest: NSObject {
    private var pending: CheckedContinuation<String, any Error>?

    /// Reduces whatever the system produced to the one string the server takes.
    ///
    /// Static and shared with `AccountSection.signIn`, which reaches the same
    /// credential through `SignInWithAppleButton` rather than through the
    /// controller below: the two downcasts are the framework's shape —
    /// `ASAuthorization.credential` is an existential and Apple ID is one of the
    /// kinds it can hold — and a second copy of them is a second place to fix
    /// when that shape or this app's handling of it changes.
    ///
    /// - Throws: `AppleIdentityRequestError.unreadableCredential` for the shape
    ///   Apple should never return but the types permit.
    static func identityToken(from authorization: ASAuthorization) throws -> String {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8)
        else {
            throw AppleIdentityRequestError.unreadableCredential
        }

        return token
    }

    /// Presents the system sheet and answers with the `identityToken` verbatim.
    ///
    /// - Throws: `ASAuthorizationError.canceled` when the person changes their
    ///   mind, which callers treat as a decision rather than a failure; whatever
    ///   `AuthenticationServices` reports otherwise; and
    ///   `AppleIdentityRequestError.unreadableCredential` for the shape Apple
    ///   should never return but the types permit.
    func freshIdentityToken() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Nothing, for the reason the sign-in button asks for nothing: the
        // server reads the token's `sub` and needs no name or address to match
        // it against the binding.
        request.requestedScopes = []

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            controller.performRequests()
        }
    }

    /// Answers the awaiting caller, exactly once.
    ///
    /// One place that clears `pending`, because the delegate has two exits and a
    /// continuation resumed twice is a crash rather than a wrong answer.
    private func finish(with result: Result<String, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}

/// Why a credential that arrived could not be used.
enum AppleIdentityRequestError: LocalizedError {
    /// Apple answered with something other than an Apple ID credential, or with
    /// one carrying no identity token. Unreachable in practice — the request
    /// above asks for exactly one kind — and surfaced rather than silently
    /// retried, because the alternative is a deletion that appears to hang.
    case unreadableCredential

    var errorDescription: String? {
        switch self {
        case .unreadableCredential:
            "Apple returned a credential this app could not read. Try again."
        }
    }
}

extension AppleIdentityRequest: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        finish(with: Result { try Self.identityToken(from: authorization) })
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        finish(with: .failure(error))
    }
}

extension AppleIdentityRequest: ASAuthorizationControllerPresentationContextProviding {
    /// The window the sheet is presented over.
    ///
    /// Read from the connected scenes rather than held, because this object
    /// exists for the length of one request and the scene it belongs to cannot
    /// change inside that. The fallback window is never presented from — a
    /// process with no foreground scene has no Settings screen to have tapped
    /// Delete on — and exists because the protocol cannot return nothing.
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
