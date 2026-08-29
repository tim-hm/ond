import Connect
import Foundation
import OndAPI
@testable import OndKit
import Testing

/// The classification the repositories were throwing away. Connect resolves a
/// `URLError` to a `Code` before anything in this app sees it —
/// `cannotConnectToHost`, `cannotFindHost` and `notConnectedToInternet` all
/// arrive as `unavailable`. Every one of them used to reach the screen as
/// Foundation's own sentence under a "the request failed: " prefix.
@Suite("Classifying a failed RPC")
struct TransportOutcomeTests {
    @Test("Each status a caller acts on differently gets its own outcome")
    func statusesMapToOutcomes() {
        #expect(TransportOutcome(code: .unavailable) == .unreachable)
        #expect(TransportOutcome(code: .deadlineExceeded) == .timedOut)
        #expect(TransportOutcome(code: .resourceExhausted) == .busy)
    }

    /// Everything left is a fault, including statuses this build has no opinion
    /// about — the `default` arm, stated as a test so that adding a case to the
    /// switch is a deliberate act rather than a silent one.
    @Test("Everything else is a fault")
    func everythingElseIsAFault() {
        for code in [Code.internalError, .unknown, .dataLoss, .aborted, .unimplemented] {
            #expect(TransportOutcome(code: code) == .serverFault, "\(code)")
        }
    }

    /// A thrown error carries its own status where it has one, and is a fault
    /// where it came from outside the transport entirely.
    @Test("A bare error is read through its Connect wrapper")
    func aBareErrorIsClassifiedThroughConnect() {
        let unavailable = ConnectError(code: .unavailable, message: "no route", exception: nil)
        #expect(TransportOutcome(error: unavailable) == .unreachable)
        #expect(TransportOutcome(error: nil) == .serverFault)
        #expect(TransportOutcome(error: CocoaError(.fileNoSuchFile)) == .serverFault)
    }

    /// The whole point of the split, stated once: what a person reads names no
    /// host, status or protocol, and what a log keeps is the transport's own
    /// words.
    @Test("The sentence a person reads keeps the transport out of it")
    func theMessageNamesNothingTechnical() {
        let jargon = ["http", "grpc", "url", "socket", "connect", "status", "rpc"]

        for outcome in [
            TransportOutcome.unreachable, .timedOut, .busy, .serverFault,
        ] {
            let message = outcome.message.lowercased()
            for word in jargon {
                #expect(!message.contains(word), "\(outcome) says \(word)")
            }
        }

        let fault = TransportFault(
            outcome: .unreachable,
            diagnostic: "Could not connect to the server."
        )
        let error = UserTechniqueRepositoryError.transport(fault)
        #expect(error.errorDescription == TransportOutcome.unreachable.message)
        #expect(error.diagnostic == "Could not connect to the server.")
    }
}
