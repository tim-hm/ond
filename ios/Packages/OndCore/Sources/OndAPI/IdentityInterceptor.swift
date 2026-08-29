import Connect
import Foundation

/// Stamps the anonymous id and, once signed in, its credential on every
/// outbound RPC. Takes closures, re-read per request, because this target
/// sits below `OndKit` and cannot name the Keychain's owner. Both
/// conformances matter: Connect dispatches streams separately, so
/// `UnaryInterceptor` alone is skipped there — `Chat` fails `UNAUTHENTICATED`.
public final class IdentityInterceptor: UnaryInterceptor, StreamInterceptor {
    /// The header the server reads. Lowercase because gRPC metadata keys are.
    public static let headerName = "ond-user-id"

    /// What proves the id above, for an identity bound to an Apple account.
    public static let credentialHeaderName = "ond-session-credential"

    private let userId: @Sendable () -> UUID?
    private let sessionCredential: @Sendable () -> String?

    public init(
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) {
        self.userId = userId
        self.sessionCredential = sessionCredential
    }

    @Sendable
    public func handleUnaryRawRequest(
        _ request: HTTPRequest<Data?>,
        proceed: @escaping @Sendable (Result<HTTPRequest<Data?>, ConnectError>) -> Void
    ) {
        proceed(.success(stamped(request)))
    }

    /// A stream's headers are settled once, when it opens — there is no
    /// per-message hook that reaches them, so this is the only place the id can
    /// join a streaming call.
    @Sendable
    public func handleStreamStart(
        _ request: HTTPRequest<Void>,
        proceed: @escaping @Sendable (Result<HTTPRequest<Void>, ConnectError>) -> Void
    ) {
        proceed(.success(stamped(request)))
    }

    /// The request with the identity on it, or unchanged when there is none.
    /// Generic over the body because the two hooks carry different ones —
    /// `Data?` unary, `Void` stream — and only the headers are touched.
    /// A credential with no id is not sent: it proves one identity, and only
    /// an unreadable Keychain can produce that state.
    private func stamped<Input: Sendable>(_ request: HTTPRequest<Input>) -> HTTPRequest<Input> {
        guard let id = userId() else {
            // No identity is not a failure to send: the catalogue is public, so
            // the app's first screen has to render before the Keychain has been
            // written. The server answers the scoped RPCs with UNAUTHENTICATED.
            return request
        }

        var headers = request.headers
        headers[Self.headerName] = [id.uuidString]

        // Absent for the majority of people, who never sign in: an identity with
        // no Apple account behind it has nothing to prove, and the server asks
        // it for nothing.
        if let credential = sessionCredential() {
            headers[Self.credentialHeaderName] = [credential]
        }

        return HTTPRequest(
            url: request.url,
            headers: headers,
            message: request.message,
            method: request.method,
            trailers: request.trailers,
            idempotencyLevel: request.idempotencyLevel
        )
    }
}
