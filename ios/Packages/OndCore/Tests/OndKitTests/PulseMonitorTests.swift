import Foundation
@testable import OndKit
import Testing

/// The phone's half of a shared pulse: the arrangement it ties to a session's
/// life, the freshness it holds a reading to, and the answer it gives the wrist.
///
/// Worth pinning because none of it is visible from the screen. A reading that
/// never expires is a badge telling somebody their heart rate is what it was when
/// they took the watch off; an answer given too generously is a wrist holding a
/// workout open for a session that ended in a pocket; an ack nobody hears is a
/// phone that never shows a badge again for the rest of a launch.
@MainActor
@Suite("Pulse monitor")
struct PulseMonitorTests {
    /// One assembled arrangement: the monitor, the outbox its order rides, the
    /// clock a reading goes stale against, and a count of context pushes.
    @MainActor
    private struct Arrangement {
        let monitor: PulseMonitor
        let orders: PlacedOrders
        let clock: ManualClock

        var pushes: Int {
            orders.pushes
        }

        func ridingOrder() async -> WatchSessionOrder? {
            await orders.riding()
        }

        /// The session the monitor follows, composed as a screen would.
        func session() -> SessionModel {
            SessionModel(
                technique: briefBreathing(cycles: 1000),
                cues: RecordingCues(),
                recorder: CapturingRecorder()
            )
        }
    }

    private func arrangement(launches: Bool = true) -> Arrangement {
        let orders = PlacedOrders()
        let clock = ManualClock()
        let monitor = PulseMonitor(
            outbox: orders.outbox,
            launcher: ScriptedLauncher(launches: launches),
            push: { orders.pushed() },
            clock: clock
        )
        return Arrangement(monitor: monitor, orders: orders, clock: clock)
    }

    /// The order has to be in the context before the launch call, which carries no
    /// payload of its own — the watch app reads why it woke from the last thing
    /// the phone said.
    @Test("Following a session places a sharing order and pushes the context")
    func placesTheOrder() async throws {
        let arrangement = arrangement()

        arrangement.monitor.follow(arrangement.session())

        let riding = try #require(await arrangement.ridingOrder())
        #expect(riding.errand == .sharePulse)
        #expect(arrangement.pushes == 1)
    }

    @Test("A reading under the arrangement's order is drawn, and asked for again")
    func acceptsAReading() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
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
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        arrangement.clock.advance(by: PulseMonitor.staleness + .seconds(1))
        try await settle { arrangement.monitor.beatsPerMinute == nil }

        #expect(arrangement.monitor.beatsPerMinute == nil)
    }

    @Test("A reading inside the freshness window keeps the badge alive")
    func aFreshReadingHoldsTheBadge() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())

        for rate in [62, 61, 60] {
            arrangement.clock.advance(by: PulseRelay.spacing)
            _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: rate))
        }
        // Past the first reading's own expiry, which the later ones re-armed.
        try await Task.sleep(for: .milliseconds(20))

        #expect(arrangement.monitor.beatsPerMinute == 60)
    }

    /// A wrist finishing with the arrangement a previous session made. Drawing it
    /// would put the last session's heart rate on this one's screen.
    @Test("A reading from another order is refused and never drawn")
    func refusesAForeignReading() {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())

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

    /// The finding that made this follow a session rather than a screen: a session
    /// with sound outlives its view, so an ending wired to a view update never
    /// arrives — and this phone, woken by each reading, would keep saying yes.
    @Test("A session that finishes ends the arrangement with no screen involved")
    func endsWhenTheSessionDoes() async throws {
        let arrangement = arrangement()
        let session = arrangement.session()
        arrangement.monitor.follow(session)
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        session.start()
        session.end()
        try await settle { arrangement.monitor.beatsPerMinute == nil }

        #expect(await arrangement.ridingOrder() == nil, "the order comes out of the context")
        #expect(!arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62)))
    }

    /// A paused session is one nobody is breathing, and a wrist should not hold a
    /// workout open for it. Resuming arranges a fresh one.
    @Test("Pausing ends the arrangement, and resuming makes another")
    func endsWhilePaused() async throws {
        let arrangement = arrangement()
        let session = arrangement.session()
        arrangement.monitor.follow(session)
        let first = try #require(await arrangement.ridingOrder())

        session.start()
        session.pause()
        try await settle { arrangement.pushes == 2 }
        #expect(await arrangement.ridingOrder() == nil)

        session.resume()
        try await settle { arrangement.pushes == 3 }
        let second = try #require(await arrangement.ridingOrder())
        #expect(second.id != first.id, "a new arrangement, not the abandoned one")
    }

    /// The ack that used to be dropped on the floor. A wrist that declines —
    /// because somebody is breathing on it — leaves the phone holding an
    /// arrangement nothing will answer, and every later session silent.
    @Test("The wrist declining ends the arrangement, so a later session can ask again")
    func endsOnADeclinedAck() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let refused = try #require(await arrangement.ridingOrder())

        arrangement.monitor.acknowledge(WatchOrderAck(orderId: refused.id, accepted: false))

        #expect(await arrangement.ridingOrder() == nil)
        arrangement.monitor.follow(arrangement.session())
        let second = try #require(await arrangement.ridingOrder())
        #expect(second.id != refused.id)
    }

    @Test("The wrist accepting changes nothing — the readings are the news")
    func keepsTheArrangementOnAnAcceptedAck() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())

        arrangement.monitor.acknowledge(WatchOrderAck(orderId: riding.id, accepted: true))

        #expect(arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62)))
    }

    /// An ack for somebody else's order — the discreet handoff's, which travels the
    /// same channel and is answered by the same message.
    @Test("An ack for another order is not this arrangement's business")
    func ignoresAForeignAck() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())

        arrangement.monitor.acknowledge(WatchOrderAck(orderId: UUID(), accepted: false))

        #expect(arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62)))
    }

    /// Both halves of ending. The retraction stops a wrist that has not opened
    /// yet; the refusal stops one that is already sharing.
    @Test("Releasing retracts the order and refuses the next reading")
    func releasingRetractsAndRefuses() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        arrangement.monitor.release()

        #expect(arrangement.monitor.beatsPerMinute == nil)
        #expect(
            await arrangement.ridingOrder() == nil,
            "a sharing order nobody wants must not ride the next ordinary push"
        )
        #expect(arrangement.pushes == 2, "the retraction has to reach the watch")
        #expect(!arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62)))
    }

    /// No watch, no watch app, or a workout already running on the wrist. There is
    /// nothing coming, so the errand must not sit in the context for every later
    /// push to carry.
    @Test("A refused launch retracts the order it was placed for")
    func retractsAfterARefusedLaunch() async throws {
        let arrangement = arrangement(launches: false)

        arrangement.monitor.follow(arrangement.session())
        // The retraction is a push of its own, which is what there is to wait for:
        // the order left the outbox in the same breath.
        try await settle { arrangement.pushes == 2 }

        #expect(await arrangement.ridingOrder() == nil)
    }

    @Test("Following a second session while one is arranged changes nothing")
    func refusesASecondArrangement() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let first = try #require(await arrangement.ridingOrder())

        arrangement.monitor.follow(arrangement.session())

        #expect(arrangement.pushes == 1, "nothing new was placed to push")
        #expect(
            arrangement.monitor.receive(WatchPulse(orderId: first.id, beatsPerMinute: 62)),
            "the first arrangement is still the live one"
        )
    }

    /// The trace is a record of what happened rather than a rate that is true
    /// now, which is why it keeps the clock's own spacing — including the
    /// re-sends of an unchanged rate that the badge deliberately ignores. A
    /// heart that held steady for eight seconds has to draw as eight seconds of
    /// level, not as a line drawn straight through the gap.
    @Test("Every reading is traced, including the ones the badge ignores")
    func tracesEveryReading() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())

        for rate in [70, 70, 68] {
            _ = arrangement.monitor.receive(
                WatchPulse(orderId: riding.id, beatsPerMinute: rate)
            )
            arrangement.clock.advance(by: PulseRelay.spacing)
        }

        #expect(arrangement.monitor.trace.readings.map(\.beatsPerMinute) == [70, 70, 68])
        #expect(
            arrangement.monitor.trace.readings.map(\.elapsed)
                == [.zero, PulseRelay.spacing, PulseRelay.spacing * 2],
            "the first reading starts the clock, and the rest are spaced by it"
        )
    }

    /// The summary is drawn after the session has finished, which is the moment
    /// the arrangement ends — so a trace cleared by that ending would leave the
    /// one screen that draws it with nothing.
    @Test("A finished session keeps its trace, though the badge goes")
    func theTraceOutlivesTheArrangement() async throws {
        let arrangement = arrangement()
        let session = arrangement.session()
        arrangement.monitor.follow(session)
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        session.start()
        session.end()
        try await settle { arrangement.monitor.beatsPerMinute == nil }

        #expect(arrangement.monitor.beatsPerMinute == nil, "a rate is only true while it arrives")
        #expect(
            arrangement.monitor.trace.readings.map(\.beatsPerMinute) == [62],
            "what already happened is still what happened"
        )
    }

    /// The drawing's width is the session's, not the sharing's. A wrist that
    /// went quiet early has to stop early on the chart — the alternative
    /// stretches a minute of readings across a fifteen-minute session and calls
    /// it a settling.
    @Test("A finished session tells its trace how long it ran")
    func closesTheTraceAtTheSessionsLength() async throws {
        let arrangement = arrangement()
        let session = arrangement.session()
        arrangement.monitor.follow(session)
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        session.start()
        arrangement.clock.advance(by: .seconds(300))
        session.end()
        try await settle { arrangement.monitor.trace.span != nil }

        #expect(arrangement.monitor.trace.span == .seconds(300))
    }

    /// Health data kept past the surface that needed it is storage by another
    /// name, and the next session must never open on the last one's line.
    @Test("Letting go of the screen forgets the readings behind it")
    func releasingForgetsTheTrace() async throws {
        let arrangement = arrangement()
        arrangement.monitor.follow(arrangement.session())
        let riding = try #require(await arrangement.ridingOrder())
        _ = arrangement.monitor.receive(WatchPulse(orderId: riding.id, beatsPerMinute: 62))

        arrangement.monitor.release()

        #expect(arrangement.monitor.trace.readings.isEmpty)
    }
}
