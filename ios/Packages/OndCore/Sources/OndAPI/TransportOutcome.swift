import Connect

/// Why an RPC came back without an answer. Connect's `Code` already draws
/// the distinction; repositories were collapsing it into `URLSession`'s
/// diagnostic sentence, which reached the screen. Lives in `OndAPI` because
/// naming `Code` is the whole of what it does; the words each case is said
/// in stay `OndKit`'s.
public enum TransportOutcome: Sendable, Equatable {
    /// Nothing answered — no route to the host, no network, or a server that is
    /// down. What a person away from signal hits, and what a development build
    /// hits every time the Mac serving it stops.
    case unreachable
    /// The request outlived its deadline. Apart from `unreachable` because a
    /// server that is merely slow is one worth asking again, and because the
    /// deadline may be this client's own rather than anything about the network.
    case timedOut
    /// Refused for now rather than for good: the server's throttle. The one
    /// outcome whose recovery is a wait rather than an action.
    case busy
    /// Something answered, and it was a fault.
    case serverFault

    /// Classifies the status Connect resolved for a failed response. Total by
    /// `default`: named refusals are caught before this is reached, and a
    /// status added to the library later is a fault with no better answer.
    public init(code: Code) {
        switch code {
        case .unavailable: self = .unreachable
        case .deadlineExceeded: self = .timedOut
        case .resourceExhausted: self = .busy
        default: self = .serverFault
        }
    }

    /// Classifies a thrown error, for streaming paths with no `ResponseMessage`.
    /// Connect resolves the underlying `URLError` to a `Code` before throwing,
    /// so re-deriving it here would copy a table the library owns. Anything
    /// that is not a `ConnectError` came from outside the transport: a fault.
    public init(error: (any Error)?) {
        self.init(code: (error as? ConnectError)?.code ?? .unknown)
    }
}

public extension ResponseMessage {
    /// Why this response carried no message. Read here so `Code` stays out of
    /// every repository's failure builder while the distinction they were
    /// discarding survives the trip into `OndKit`.
    var transportOutcome: TransportOutcome {
        TransportOutcome(code: code)
    }
}
