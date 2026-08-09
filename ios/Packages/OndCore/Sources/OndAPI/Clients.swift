import Connect
import Foundation

/// Builds the generated service clients against a configured backend.
///
/// The transport is fixed here rather than at each call site: every client must
/// agree on protocol, codec, and the two identity headers, and the one place
/// that is guaranteed is the place they are all constructed.
///
/// The per-service factories below are deliberately undocumented: each is one
/// line whose signature says the whole of it, and this paragraph is the shared
/// why. The deadlines are where the decisions live, and they carry the docs.
public enum OndClients {
    /// The deadline every unary RPC carries: enforced client-side by Connect
    /// and stamped on the request as `grpc-timeout`, so the server also learns
    /// how long the caller will wait.
    ///
    /// URLSession's own 60-second idle timer is not a timeout a person waits
    /// out: an unreachable backend — the dev Mac that has moved, a box
    /// mid-deploy — reads as "never loads" rather than "cannot connect", and
    /// every screen behind it holds a spinner for the whole minute. Ten seconds
    /// is far past a healthy round trip to a handler whose work is one database
    /// query, and short enough that the failure arrives while somebody is still
    /// looking at the screen.
    private static let requestDeadline: TimeInterval = 10

    /// The account service's deadline, above the ten seconds everything else
    /// gets.
    ///
    /// `DeleteAccount` reads the binding under `FOR UPDATE` and may verify a
    /// fresh Apple identity token, which on a cold key cache fetches Apple's
    /// JWKS — an outbound HTTPS round trip inside the RPC, bounded server-side
    /// at ten seconds (`apple.rs`). A client that gives up first is told
    /// nothing while the server goes on to commit: the row is erased, the
    /// device keeps its id and shows "deletion failed" — the opposite of the
    /// truth. Sitting well above the server's own bound means a stall surfaces
    /// as the server's error with the server's reason, by the same argument the
    /// assistant's idle timer makes.
    private static let accountDeadline: TimeInterval = 30

    /// How long the assistant's stream may go silent between chunks before the
    /// connection is abandoned.
    ///
    /// URLSession's request timer is an idle timer — it resets on every chunk —
    /// so on a stream it bounds the gap between chunks rather than the answer,
    /// which a total deadline like `requestDeadline` cannot express: any fixed
    /// deadline either cuts a long answer mid-sentence or allows a stall that
    /// long. Forty seconds sits deliberately above the 30 seconds `bedrock.rs`
    /// allows between reads before it calls the provider stalled, so a stalled
    /// generation fails as the server's error with the server's reason rather
    /// than as a bare client timeout.
    private static let streamingIdleTimeout: TimeInterval = 40

    /// One `URLSession` for every unary service, not one per service.
    ///
    /// `ProtocolClient` builds its own `URLSessionHTTPClient` — and therefore
    /// its own session — by default, so a second service would otherwise mean a
    /// second connection pool to the same host: another TCP and TLS handshake,
    /// and no multiplexing between the catalogue call and the profile sync that
    /// launch fires alongside it. Deadlines are per-request
    /// (`ProtocolClientConfig.timeout`), not per-session, so this one pool
    /// serves every unary service however long each is allowed to take; the
    /// session's default 60-second idle timer stays only as the transport
    /// backstop behind those deadlines.
    private static let httpClient = URLSessionHTTPClient()

    /// The second pool, and the only thing that justifies one: an idle timer is
    /// a session-level setting, and the assistant is the one service that needs
    /// its timeout to be one. It costs a handshake on the first coach message,
    /// which is a screen somebody has deliberately opened rather than one
    /// launch races through.
    private static let streamingHTTPClient: URLSessionHTTPClient = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = streamingIdleTimeout
        return URLSessionHTTPClient(configuration: configuration)
    }()

    public static func techniqueService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_TechniqueServiceClient {
        Ond_V1_TechniqueServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential
        ))
    }

    public static func userTechniqueService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_UserTechniqueServiceClient {
        Ond_V1_UserTechniqueServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential
        ))
    }

    public static func profileService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_ProfileServiceClient {
        Ond_V1_ProfileServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential
        ))
    }

    public static func journeyService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_JourneyServiceClient {
        Ond_V1_JourneyServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential
        ))
    }

    public static func assistantService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_AssistantServiceClient {
        // No deadline: a coach answer legitimately outlasts any total bound
        // worth having, so the stream is bounded per-gap by its session's idle
        // timer instead.
        Ond_V1_AssistantServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential,
            deadline: nil,
            over: streamingHTTPClient
        ))
    }

    public static func accountService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_AccountServiceClient {
        Ond_V1_AccountServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential,
            deadline: accountDeadline
        ))
    }

    public static func entitlementService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?
    ) -> Ond_V1_EntitlementServiceClient {
        Ond_V1_EntitlementServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            sessionCredential: sessionCredential
        ))
    }

    private static func protocolClient(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
        sessionCredential: @escaping @Sendable () -> String?,
        deadline: TimeInterval? = OndClients.requestDeadline,
        over httpClient: URLSessionHTTPClient = OndClients.httpClient
    ) -> ProtocolClient {
        ProtocolClient(
            httpClient: httpClient,
            config: ProtocolClientConfig(
                host: baseURL.absoluteString,
                // gRPC-Web, not Connect: the server is tonic behind
                // `tonic_web::GrpcWebLayer`, which serves gRPC-Web. Switching
                // this to `.connect` produces requests the server answers with
                // an unimplemented status. docs/transport.md has the full
                // reasoning.
                networkProtocol: .grpcWeb,
                // Binary protobuf. `JSONCodec` is the library default and would
                // silently disagree with the server's content type.
                codec: ProtoCodec(),
                timeout: deadline,
                // Applied to every client, including the catalogue's: the server
                // creates a person's row on the first RPC of any kind, so the
                // identity has to travel on the public calls too.
                interceptors: [InterceptorFactory { _ in
                    IdentityInterceptor(userId: userId, sessionCredential: sessionCredential)
                }]
            )
        )
    }
}
