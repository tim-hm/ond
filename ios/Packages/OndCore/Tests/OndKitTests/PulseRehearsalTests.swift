import Foundation
@testable import OndKit
import Testing

/// The stand-in wrist: what a monitor does when it is told to invent readings
/// rather than ask for them.
///
/// Pinned here because the machine the affordance exists for is the one machine
/// that cannot check it. A rehearsal compiled behind `targetEnvironment(simulator)`
/// would be dead on this host — where the package's tests run — and so untestable
/// by construction. It is a flag the composition root passes instead, which is
/// the whole reason this suite can ask for one.
@MainActor
@Suite("Rehearsing a wrist")
struct PulseRehearsalTests {
    @MainActor
    private struct Arrangement {
        let monitor: PulseMonitor
        let orders: PlacedOrders
        let clock: ManualClock

        func session() -> SessionModel {
            SessionModel(
                technique: briefBreathing(cycles: 1000),
                cues: RecordingCues(),
                recorder: CapturingRecorder()
            )
        }
    }

    private func arrangement(rehearsing: Bool = true) -> Arrangement {
        let orders = PlacedOrders(tier: .plus)
        let clock = ManualClock()
        return Arrangement(
            monitor: PulseMonitor(
                outbox: orders.outbox,
                launcher: ScriptedLauncher(launches: true),
                push: { orders.pushed() },
                clock: clock,
                rehearsing: rehearsing
            ),
            orders: orders,
            clock: clock
        )
    }

    /// The contrast case, and the one that ships: every session on a real phone
    /// passes through `follow`, so the preference has to be what stops it. A
    /// screen keeps no place for a rate it will never be sent.
    @Test("A monitor that is not rehearsing follows nothing unasked")
    func followsNothingUnasked() async {
        let arrangement = arrangement(rehearsing: false)

        arrangement.monitor.follow(arrangement.session(), wanted: false)

        #expect(!arrangement.monitor.expectsReadings)
        #expect(await arrangement.orders.riding() == nil)
        #expect(arrangement.monitor.beatsPerMinute == nil)
    }

    /// The readings arrive on the wrist's own spacing and through the path a real
    /// one takes, which is what makes a rehearsed session worth looking at: the
    /// trace fills as the summary will draw it.
    @Test("A rehearsing monitor draws a heart no wrist sent")
    func drawsAnInventedHeart() async throws {
        let arrangement = arrangement()

        // Unasked deliberately: the preference is paywalled and a simulator has
        // no wrist for it to be about, so a rehearsal follows without it.
        arrangement.monitor.follow(arrangement.session(), wanted: false)
        try await settle { arrangement.monitor.beatsPerMinute != nil }
        #expect(arrangement.monitor.expectsReadings)
        #expect(arrangement.monitor.beatsPerMinute == PulseMonitor.rehearsedRate(after: 0))

        arrangement.clock.advance(by: PulseRelay.spacing)
        try await settle {
            arrangement.monitor.beatsPerMinute == PulseMonitor.rehearsedRate(after: 1)
        }
        #expect(arrangement.monitor.trace.readings.count == 2)
    }

    /// Nothing is asked of a wrist that is not there. An order riding the context
    /// would wake a watch app on a paired phone and hold a workout open on it for
    /// readings this monitor is inventing anyway.
    @Test("A rehearsal orders no wrist and pushes no context")
    func ordersNoWrist() async throws {
        let arrangement = arrangement()

        arrangement.monitor.follow(arrangement.session(), wanted: false)
        try await settle { arrangement.monitor.beatsPerMinute != nil }

        #expect(await arrangement.orders.riding() == nil)
        #expect(arrangement.orders.pushes == 0)
    }

    /// A following arrangement like any other: a session nobody is breathing gets
    /// no readings, so a simulator cannot show a badge a phone would not.
    @Test("A finished session ends the rehearsal")
    func endsWithTheSession() async throws {
        let arrangement = arrangement()
        let session = arrangement.session()
        arrangement.monitor.follow(session, wanted: false)
        session.start()
        try await settle { arrangement.monitor.beatsPerMinute != nil }

        session.end()
        try await settle { arrangement.monitor.beatsPerMinute == nil }

        #expect(arrangement.monitor.beatsPerMinute == nil)
    }
}
