import Connect

/// Why an RPC came back without an answer.
///
/// Connect already draws this distinction and every repository threw it away.
/// A failed response carries a `Code` — `.unavailable` for a host that could
/// not be reached, `.deadlineExceeded` for one that took too long — and the
/// failure builders read it only for the refusals they name, collapsing
/// everything else into one case carrying `URLSession`'s own sentence. That
/// sentence is a diagnostic, and it was reaching the screen: somebody whose
/// exercises had not loaded was being told "Could not connect to the server."
///
/// Lives in `OndAPI` because naming `Code` is the whole of what it does, and
/// Connect is this target's dependency rather than `OndKit`'s. The words each
/// case is said in are `OndKit`'s, beside the rest of the app's voice.
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

    /// Classifies the status Connect resolved for a failed response.
    ///
    /// Total by `default` rather than by listing every remaining `Code`: the
    /// refusals a repository names are caught before this is reached, and a
    /// status added to the library later is a fault this app has no better
    /// answer for than the one it gives every other fault.
    public init(code: Code) {
        switch code {
        case .unavailable: self = .unreachable
        case .deadlineExceeded: self = .timedOut
        case .resourceExhausted: self = .busy
        default: self = .serverFault
        }
    }

    /// Classifies a thrown error, for the streaming paths that have no
    /// `ResponseMessage` to read a status from.
    ///
    /// Connect wraps the underlying `URLError` and resolves it to a `Code`
    /// before throwing, so reading the wrapper is enough — unwrapping to the
    /// `URLError` and re-deriving the status here would be a second copy of a
    /// table the library already owns. Anything that is not a `ConnectError`
    /// reached us from outside the transport and is a fault by default.
    public init(error: (any Error)?) {
        self.init(code: (error as? ConnectError)?.code ?? .unknown)
    }
}

public extension ResponseMessage {
    /// Why this response carried no message.
    ///
    /// Read here so that `Code` stays out of every repository's failure
    /// builder — the reason those builders take flags rather than the status
    /// itself — while the distinction they were discarding survives the trip
    /// into `OndKit`.
    var transportOutcome: TransportOutcome {
        TransportOutcome(code: code)
    }
}
