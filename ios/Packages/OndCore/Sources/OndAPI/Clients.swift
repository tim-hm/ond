import Connect
import Foundation

/// Builds the generated service clients against a configured backend.
///
/// The transport is fixed here rather than at each call site: every client must
/// agree on protocol, codec, and the identity header, and the one place that is
/// guaranteed is the place they are all constructed.
public enum OndClients {
    /// How long a request may go without receiving any data before URLSession
    /// abandons it.
    ///
    /// URLSession's default is 60 seconds, which is not a timeout a person
    /// waits out: an unreachable backend — the dev Mac that has moved, a box
    /// mid-deploy — reads as "never loads" rather than "cannot connect", and
    /// every screen behind it holds a spinner for the whole minute. Ten seconds
    /// is far past a healthy round trip to a handler whose work is one database
    /// query, and short enough that the failure arrives while somebody is still
    /// looking at the screen.
    private static let requestTimeout: TimeInterval = 10

    /// The same allowance for the assistant, whose RPCs stream.
    ///
    /// The timer is an idle timer — it resets on every chunk — so on a stream it
    /// bounds the gap between chunks rather than the answer. Ten seconds would
    /// therefore cut a model that thinks before it speaks, and it would cut it
    /// *sooner than the server does*: `bedrock.rs` allows 30 seconds between
    /// reads before it calls the provider stalled. This sits above that
    /// deliberately, so a stalled generation fails as the server's error with
    /// the server's reason rather than as a bare client timeout.
    private static let streamingRequestTimeout: TimeInterval = 40

    /// One `URLSession` for every unary service, not one per service.
    ///
    /// `ProtocolClient` builds its own `URLSessionHTTPClient` — and therefore
    /// its own session — by default, so a second service would otherwise mean a
    /// second connection pool to the same host: another TCP and TLS handshake,
    /// and no multiplexing between the catalogue call and the profile sync that
    /// launch fires alongside it.
    private static let httpClient = session(timeout: requestTimeout)

    /// The second pool, and the only thing that justifies one: a session carries
    /// exactly one timeout, and the assistant's needs to be four times the rest.
    /// It costs a handshake on the first coach message, which is a screen
    /// somebody has deliberately opened rather than one launch races through.
    private static let streamingHTTPClient = session(timeout: streamingRequestTimeout)

    private static func session(timeout: TimeInterval) -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        return URLSessionHTTPClient(configuration: configuration)
    }

    public static func techniqueService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_TechniqueServiceClient {
        Ond_V1_TechniqueServiceClient(client: protocolClient(baseURL: baseURL, userId: userId))
    }

    public static func userTechniqueService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_UserTechniqueServiceClient {
        Ond_V1_UserTechniqueServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId
        ))
    }

    public static func profileService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_ProfileServiceClient {
        Ond_V1_ProfileServiceClient(client: protocolClient(baseURL: baseURL, userId: userId))
    }

    public static func journeyService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_JourneyServiceClient {
        Ond_V1_JourneyServiceClient(client: protocolClient(baseURL: baseURL, userId: userId))
    }

    public static func assistantService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_AssistantServiceClient {
        Ond_V1_AssistantServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId,
            over: streamingHTTPClient
        ))
    }

    public static func accountService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_AccountServiceClient {
        Ond_V1_AccountServiceClient(client: protocolClient(baseURL: baseURL, userId: userId))
    }

    public static func entitlementService(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?
    ) -> Ond_V1_EntitlementServiceClient {
        Ond_V1_EntitlementServiceClient(client: protocolClient(
            baseURL: baseURL,
            userId: userId
        ))
    }

    private static func protocolClient(
        baseURL: URL,
        userId: @escaping @Sendable () -> UUID?,
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
                // Applied to every client, including the catalogue's: the server
                // creates a person's row on the first RPC of any kind, so the
                // identity has to travel on the public calls too.
                interceptors: [InterceptorFactory { _ in IdentityInterceptor(userId: userId) }]
            )
        )
    }
}
