import Connect
import Foundation

/// Puts this install's anonymous id — and, once it has signed in, the
/// credential proving that id is its own — on every outbound RPC.
///
/// One interceptor rather than a `headers:` argument at each call site: neither
/// header is optional per-call, and a repository that forgot one would fail only
/// against the services that require it — which is the half of the API nobody
/// tests by hand.
///
/// The credential travels as a header rather than as a field on each request
/// message because the thing it proves already does, because a stream settles
/// its headers once at open and has no per-message hook, and because the server
/// checks it at one choke point in front of every identified service rather
/// than in each handler.
///
/// Takes closures rather than a store type because this target sits below
/// `OndKit` in the module graph and cannot name the protocol that owns the
/// Keychain. They are `@Sendable` and re-read per request, so an identity minted
/// — or a credential adopted — after the client was built is still picked up.
///
/// Both halves of the seam, and that is the whole point. Connect dispatches
/// unary calls and streams through separate protocols, so a `UnaryInterceptor`
/// alone is silently skipped on every server-streaming RPC — the header simply
/// never goes out and the server answers `UNAUTHENTICATED`. That is not a
/// visible wiring error either: the unary calls keep working, so the app looks
/// healthy while `Chat` fails on every attempt. Adding a streaming RPC means
/// nothing here; dropping `StreamInterceptor` breaks all of them at once.
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
    ///
    /// Generic over the body because the two hooks above carry different ones —
    /// `Data?` for a unary call, `Void` for a stream opening — and the headers
    /// are the only thing either of them touches.
    ///
    /// A credential with no id to go with it is not sent. It proves one
    /// identity, so on a request that names none it is a value with nothing to
    /// say — and the Keychain being unreadable is the only way to reach that.
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
