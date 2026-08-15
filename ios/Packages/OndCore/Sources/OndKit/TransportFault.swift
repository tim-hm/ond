import Foundation
import OndAPI

/// A failed RPC, told twice: once for the person and once for the log.
///
/// The two were one string, and that is the defect this type exists to close.
/// Every repository's `.transport` case carried `URLSession`'s own sentence,
/// `errorDescription` prefixed it with "the request failed: ", and the result
/// went to `Logger` and to the screen alike — so somebody whose exercises had
/// not loaded read "the request failed: Could not connect to the server."
///
/// The diagnostic is the half worth keeping in the log: it names the host, the
/// status, the actual `URLError`. It is also the half nobody can act on, which
/// is why it no longer leaves the device through the interface.
public struct TransportFault: Sendable, Equatable {
    /// What happened, classified — the half a screen words.
    public let outcome: TransportOutcome
    /// What the transport said, verbatim — the half a log keeps.
    public let diagnostic: String

    public init(outcome: TransportOutcome, diagnostic: String) {
        self.outcome = outcome
        self.diagnostic = diagnostic
    }
}

public extension TransportOutcome {
    /// What a person is told, when they have to be told anything.
    ///
    /// One sentence per outcome, written once. Each says what happened and,
    /// where there is one, what the person can do; none names a host, a status
    /// or a protocol, because none of those is theirs to act on.
    ///
    /// None ends in "try again" either — every one of these appears beside a
    /// control that says exactly that, and a sentence repeating its own button
    /// is the app saying it twice.
    var message: String {
        switch self {
        case .unreachable: "Can't reach the server just now."
        case .timedOut: "The server took too long to answer."
        case .busy: "The server is busy — give it a moment."
        case .serverFault: "Something went wrong at our end."
        }
    }
}

/// An error carrying a developer-facing diagnostic distinct from the sentence
/// it shows a person.
///
/// The seven repository error enums conform. Without it every `catch` would
/// have to switch over which repository it came from to log anything useful,
/// which is the same seven-way duplication in a new place.
public protocol DiagnosticCarrying: Error {
    /// The transport's own words, for a log line and never for a screen.
    var diagnostic: String { get }
}

public extension Error {
    /// The diagnostic where the error carries one, and its description where it
    /// does not — an `ASAuthorizationError` or a `DecodingError` has only the
    /// one text, and it is already developer-facing.
    ///
    /// Reads through the conformance rather than recursing: the protocol
    /// declares no default, so a conforming type always supplies its own.
    var diagnostic: String {
        (self as? any DiagnosticCarrying)?.diagnostic ?? localizedDescription
    }
}
