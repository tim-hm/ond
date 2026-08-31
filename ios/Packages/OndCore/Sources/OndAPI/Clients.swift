import Connect
import Foundation

/// Builds the generated service clients against a configured backend.
/// The transport is fixed here, not per call site: every client must agree
/// on protocol, codec, and the two identity headers. The one-line factories
/// are deliberately undocumented; the deadlines carry the decisions.
public enum OndClients {
    /// The deadline every unary RPC carries: enforced client-side and stamped
    /// on the request as `grpc-timeout`. URLSession's own 60-second idle timer
    /// would hold a spinner for a full minute against an unreachable backend;
    /// ten seconds is far past a healthy round trip and fails while somebody
    /// is still looking at the screen.
    private static let requestDeadline: TimeInterval = 10

    /// Above the ten seconds everything else gets: `DeleteAccount` may fetch
    /// Apple's JWKS inside the RPC, bounded server-side at ten seconds
    /// (`apple.rs`). A client that gives up first shows "deletion failed"
    /// while the server goes on to erase the row. Sitting above the server's
    /// bound means a stall surfaces as the server's error, with its reason.
    private static let accountDeadline: TimeInterval = 30

    /// How long the assistant's stream may go silent between chunks before the
    /// connection is abandoned. URLSession's request timer resets on every
    /// chunk, so it bounds the gap, not the answer — a total deadline cannot.
    /// Forty sits deliberately above the 30 seconds `assistant/model/bedrock/` allows between
    /// reads, so a stalled generation fails as the server's error.
    private static let streamingIdleTimeout: TimeInterval = 40

    /// One `URLSession` for every unary service: `ProtocolClient` otherwise
    /// builds its own, so each service would open a second pool to the same
    /// host — another TLS handshake, no multiplexing at launch. Deadlines are
    /// per-request (`ProtocolClientConfig.timeout`), not per-session, so one
    /// pool serves them all; the 60-second idle timer stays as the backstop.
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
