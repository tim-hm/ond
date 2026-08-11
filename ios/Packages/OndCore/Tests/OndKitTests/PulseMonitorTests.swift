import Foundation
@testable import OndKit
import Testing

/// The phone's half of a shared pulse: the arrangement it makes, the freshness it
/// holds a reading to, and the answer it gives the wrist.
///
/// Worth pinning because the two things this decides are both invisible from the
/// screen. A reading that never expires is a badge telling somebody their heart
/// rate is what it was when they took the watch off; an answer given too
/// generously is a wrist holding a workout open for a session that has ended.
@MainActor
@Suite("Pulse monitor")
struct PulseMonitorTests {
    /// One assembled arrangement: the monitor, the outbox its order rides, the
    /// clock a reading goes stale against, and a count of context pushes.
    @MainActor
    private struct Arrangement {
        let monitor: PulseMonitor
        let outbox: WatchHandoffOutbox
        let clock: ManualClock
        let pushes: () -> Int

        /// What the outbox would hand the radio right now — nil when no order is
        /// riding, which is how a retraction is observable from outside.
        func ridingOrder() async -> WatchSessionOrder? {
            var handed: WatchSessionOrder?
            await outbox.handOver { handed = $0.order }
            return handed
        }

        /// Begins, and waits for the launch it starts to have run its course.
        func begin() async throws {
            let pushed = pushes()
            monitor.begin()
            try await settle { pushes() > pushed }
        }
    }

    private func arrangement(launches: Bool = true) -> Arrangement {
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores()
        )
        let clock = ManualClock()
        var pushes = 0
        let monitor = PulseMonitor(
            outbox: outbox,
            launcher: ScriptedLauncher(launches: launches),
            push: { pushes += 1 },
            clock: clock
        )
        return Arrangement(monitor: monitor, outbox: outbox, clock: clock, pushes: { pushes })
    }

    /// The order has to be in the context before the launch call, which carries no
    /// payload of its own — the watch app reads why it woke from the last thing
    /// the phone said.
    @Test("Beginning places a sharing order and pushes the context")
    func placesTheOrder() async throws {
        let arrangement = arrangement()

        try await arrangement.begin()

        let riding = try #require(await arrangement.ridingOrder())
        #expect(riding.errand == .sharePulse)
        #expect(arrangement.pushes() == 1)
    }

    @Test("A reading under the arrangement's order is drawn, and asked for again")
    func acceptsAReading() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()
        let riding = try #require(await arrangement.ridingOrder())

        let isWanted = arrangement.monitor.receive(
            WatchPulse(orderId: riding.id, beatsPerMinute: 62)
        )

        #expect(isWanted)
        #expect(arrangement.monitor.beatsPerMinute == 62)
    }

    /// The freshness rule. A wrist that goes quiet — taken off, out of range, a
    /// watch app somebody force-quit — leaves its last number behind, and a badge
    /// that kept showing it would be reporting a heart rate as a fact.
    @Test("A reading nothing follows stops being drawn")
    func expiresAStaleReading() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()
        let riding = try #require(await arrangement.ridingOrder())
        arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        arrangement.clock.advance(by: PulseMonitor.staleness + .seconds(1))
        try await settle { arrangement.monitor.beatsPerMinute == nil }

        #expect(arrangement.monitor.beatsPerMinute == nil)
    }

    @Test("A reading inside the freshness window keeps the badge alive")
    func aFreshReadingHoldsTheBadge() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()
        let riding = try #require(await arrangement.ridingOrder())

        for rate in [62, 61, 60] {
            arrangement.clock.advance(by: PulseRelay.spacing)
            arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: rate))
        }
        // Past the first reading's own expiry, which the later ones re-armed.
        try await Task.sleep(for: .milliseconds(20))

        #expect(arrangement.monitor.beatsPerMinute == 60)
    }

    /// A wrist finishing with the arrangement a previous session made. Drawing it
    /// would put the last session's heart rate on this one's screen.
    @Test("A reading from another order is refused and never drawn")
    func refusesAForeignReading() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()

        let isWanted = arrangement.monitor.receive(
            WatchPulse(orderId: UUID(), beatsPerMinute: 62)
        )

        #expect(!isWanted)
        #expect(arrangement.monitor.beatsPerMinute == nil)
    }

    /// The case a stop message could never cover: this phone was killed and
    /// relaunched in the background to take the reading itself, so it has no
    /// session and no arrangement. Answering no is what puts the sensor down.
    @Test("A phone with nothing arranged refuses every reading")
    func refusesAReadingItNeverAskedFor() {
        let arrangement = arrangement()

        #expect(!arrangement.monitor.receive(WatchPulse(orderId: UUID(), beatsPerMinute: 62)))
    }

    /// Both halves of ending. The retraction stops a wrist that has not opened
    /// yet; the refusal stops one that is already sharing.
    @Test("Ending retracts the order and refuses the next reading")
    func endingRetractsAndRefuses() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()
        let riding = try #require(await arrangement.ridingOrder())
        arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        arrangement.monitor.end()

        #expect(arrangement.monitor.beatsPerMinute == nil)
        #expect(
            await arrangement.ridingOrder() == nil,
            "a sharing order nobody wants must not ride the next ordinary push"
        )
        #expect(arrangement.pushes() == 2, "the retraction has to reach the watch")
        #expect(!arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62)))
    }

    /// No watch, no watch app, or a workout already running on the wrist. There is
    /// nothing coming, so the errand must not sit in the context for every later
    /// push to carry.
    @Test("A refused launch retracts the order it was placed for")
    func retractsAfterARefusedLaunch() async throws {
        let arrangement = arrangement(launches: false)

        arrangement.monitor.begin()
        // The retraction is a push of its own, which is what there is to wait for:
        // the order left the outbox in the same breath.
        try await settle { arrangement.pushes() == 2 }

        #expect(await arrangement.ridingOrder() == nil)
    }

    @Test("A second beginning while one is arranged changes nothing")
    func refusesASecondArrangement() async throws {
        let arrangement = arrangement()
        try await arrangement.begin()
        let first = try #require(await arrangement.ridingOrder())

        arrangement.monitor.begin()

        #expect(arrangement.pushes() == 1, "nothing new was placed to push")
        #expect(
            arrangement.monitor.receive(WatchPulse(orderId: first.id, beatsPerMinute: 62)),
            "the first arrangement is still the live one"
        )
    }
}
