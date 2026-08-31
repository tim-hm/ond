import Foundation
import OndAPI

/// A failed RPC, told twice: once for the person and once for the log. The
/// diagnostic names the host, the status, the actual `URLError` — the half
/// worth logging, and the half nobody can act on, so it never reaches the
/// screen.
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
    /// What a person is told, when they have to be told anything. No sentence
    /// names a host, a status or a protocol — none is theirs to act on — and
    /// none ends in "try again", because each appears beside a control that
    /// says exactly that.
    var message: String {
        switch self {
        case .unreachable: "Can't reach the server just now."
        case .timedOut: "The server took too long to answer."
        case .busy: "The server is busy. Try again shortly."
        case .serverFault: "Something went wrong at our end."
        }
    }
}

/// An error carrying a developer-facing diagnostic distinct from the sentence
/// it shows a person. The repository error enums conform, so a `catch` can
/// log usefully without switching over which repository it came from.
public protocol DiagnosticCarrying: Error {
    /// The transport's own words, for a log line and never for a screen.
    var diagnostic: String { get }
}

public extension Error {
    /// The diagnostic where the error carries one, and its description where
    /// it does not. Reads through the conformance rather than recursing: the
    /// protocol declares no default, so a conforming type supplies its own.
    var diagnostic: String {
        (self as? any DiagnosticCarrying)?.diagnostic ?? localizedDescription
    }
}
