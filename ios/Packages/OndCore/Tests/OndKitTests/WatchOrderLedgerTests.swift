import Foundation
@testable import OndKit
import Testing

/// The replay guard under the phone's session orders.
///
/// Worth pinning because both of its failure modes buzz a wrist that asked for
/// nothing: an order admitted twice runs a half-hour session on every
/// activation for as long as the context stands, and a stale one admitted at
/// all starts a session whose moment passed hours ago.
@MainActor
@Suite("Watch order ledger")
struct WatchOrderLedgerTests {
    private func freshLedger() throws -> WatchOrderLedger {
        try WatchOrderLedger(defaults: #require(
            UserDefaults(suiteName: "order-ledger-tests.\(UUID().uuidString)")
        ))
    }

    private func order(issuedAt: Date) -> WatchSessionOrder {
        WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: issuedAt
        )
    }

    /// The system replays the last context on every activation, so the second
    /// sight of an order is the overwhelmingly common one — and it is the
    /// launch after next, not a variant to tolerate.
    @Test("An order is admitted exactly once")
    func admitsAnOrderOnce() throws {
        let ledger = try freshLedger()
        let now = Date(timeIntervalSince1970: 1_754_900_000)
        let placed = order(issuedAt: now)

        #expect(ledger.admit(placed, at: now))
        #expect(!ledger.admit(placed, at: now))
    }

    /// The replay outlives the process: the context that launched this run is
    /// redelivered to the next one, so a ledger that forgot at exit would run
    /// the same order once per launch.
    @Test("An executed order stays refused across a relaunch")
    func remembersAcrossARelaunch() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "order-ledger-tests.relaunch.\(UUID().uuidString)")
        )
        let now = Date(timeIntervalSince1970: 1_754_900_000)
        let placed = order(issuedAt: now)

        #expect(WatchOrderLedger(defaults: defaults).admit(placed, at: now))
        #expect(
            !WatchOrderLedger(defaults: defaults).admit(placed, at: now),
            "a fresh process must still know the order ran"
        )
    }

    /// The order the freshness window exists for: issued while the watch was
    /// off its wrist, delivered when it next activates — at midnight, on a
    /// charger, hours after the meeting it named.
    @Test("An order past the freshness window is refused")
    func refusesAStaleOrder() throws {
        let ledger = try freshLedger()
        let issued = Date(timeIntervalSince1970: 1_754_900_000)

        let stale = order(issuedAt: issued)
        let lateEnough = issued.addingTimeInterval(WatchOrderLedger.freshness + 1)

        #expect(!ledger.admit(stale, at: lateEnough))
    }

    /// The two devices keep separate clocks, and the phone's may run ahead of
    /// the wrist's. An order from the apparent near future is skew, not
    /// staleness — refusing it would break the handoff for anyone whose
    /// watch sets its clock a beat behind.
    @Test("An order from a slightly fast phone clock is admitted")
    func toleratesClockSkew() throws {
        let ledger = try freshLedger()
        let now = Date(timeIntervalSince1970: 1_754_900_000)

        let fromTheFuture = order(issuedAt: now.addingTimeInterval(90))

        #expect(ledger.admit(fromTheFuture, at: now))
    }

    /// Refusal must not record: an order turned away for staleness was never
    /// run, and the ledger's memory is of orders that were.
    @Test("A refused order is not remembered as executed")
    func aRefusalRecordsNothing() throws {
        let ledger = try freshLedger()
        let issued = Date(timeIntervalSince1970: 1_754_900_000)
        let placed = order(issuedAt: issued)

        #expect(!ledger.admit(
            placed,
            at: issued.addingTimeInterval(WatchOrderLedger.freshness + 1)
        ))
        #expect(
            ledger.admit(placed, at: issued),
            "the same order inside the window is still runnable"
        )
    }
}
