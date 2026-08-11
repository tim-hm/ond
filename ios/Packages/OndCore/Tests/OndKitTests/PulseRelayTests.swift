import Foundation
@testable import OndKit
import Testing

/// The wrist's pacing, and the two ways it stops sharing.
///
/// Worth pinning because both failures are invisible where the code runs. Send too
/// often and a wrist somebody is wearing for half an hour loses its afternoon;
/// forget to stop and it holds a workout session open for a session that ended,
/// which on a real device looks like nothing at all until the battery says so.
@MainActor
@Suite("Pulse relay")
struct PulseRelayTests {
    /// A phone whose answer the test scripts, counting what actually reached it.
    @MainActor
    private final class Phone {
        private(set) var readings: [Int] = []
        var isWanted = true
        /// Whether a send simply never comes back — a radio waiting out its own
        /// timeout, which on WatchConnectivity is the best part of a minute.
        var hangs = false

        func send(_ pulse: WatchPulse) async -> Bool {
            readings.append(pulse.beatsPerMinute)
            while hangs, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            return isWanted
        }
    }

    /// One assembled arrangement: the relay, the phone at the other end, and the
    /// clock its pacing runs on.
    @MainActor
    private struct Arrangement {
        let relay: PulseRelay
        let phone: Phone
        let clock: ManualClock
        let order: WatchSessionOrder

        /// Offers a reading and waits for the send it may have started, so the
        /// assertion after it reads a settled relay.
        func report(_ rate: Double) async throws {
            let delivered = phone.readings.count
            relay.report(rate)
            try await settle { phone.readings.count > delivered }
        }

        /// Offers a reading that should go nowhere, and gives the relay a moment
        /// to prove it. A nap rather than `settle` for `WristLaunchModel`'s
        /// reason: there is no condition to poll for when the expectation is that
        /// nothing happens.
        func reportWithoutSending(_ rate: Double) async throws {
            relay.report(rate)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func arrangement() -> Arrangement {
        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)
        let clock = ManualClock()
        let phone = Phone()
        let relay = PulseRelay(
            order: order,
            send: { [phone] in await phone.send($0) },
            clock: clock
        )
        return Arrangement(relay: relay, phone: phone, clock: clock, order: order)
    }

    @Test("The first reading goes out at once, under the order that asked for it")
    func sendsTheFirstReading() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        try await arrangement.report(61.4)

        #expect(arrangement.phone.readings == [61], "rounded to the beats a badge shows")
        #expect(arrangement.relay.beatsPerMinute == 61)
    }

    /// The pacing. HealthKit hands over several samples in one batch often enough,
    /// and a relay that sent each of them would spend a radio on one number.
    @Test("A second reading inside the spacing is held back")
    func holdsBackABurst() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        try await arrangement.report(61)

        try await arrangement.reportWithoutSending(62)

        #expect(arrangement.phone.readings == [61])
        #expect(
            arrangement.relay.beatsPerMinute == 62,
            "the wrist's own screen still shows what the sensor just said"
        )
    }

    @Test("A reading after the spacing goes out")
    func sendsAgainOnceTheSpacingHasPassed() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        try await arrangement.report(61)

        arrangement.clock.advance(by: PulseRelay.spacing)
        try await arrangement.report(64)

        #expect(arrangement.phone.readings == [61, 64])
    }

    /// The same whole number twice is still sent. Skipping it is the obvious
    /// saving and the trap: a resting heart reads 58 for half a minute, and the
    /// phone would call the badge stale while the wrist was working perfectly.
    @Test("An unchanged rate is sent again rather than skipped")
    func sendsAnUnchangedRate() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        try await arrangement.report(58)

        arrangement.clock.advance(by: PulseRelay.spacing)
        try await arrangement.report(58)

        #expect(arrangement.phone.readings == [58, 58])
    }

    @Test("A rate of zero is the sensor saying nothing, and is not sent")
    func ignoresAnEmptyReading() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        try await arrangement.reportWithoutSending(0)

        #expect(arrangement.phone.readings.isEmpty)
        #expect(arrangement.relay.beatsPerMinute == nil)
    }

    /// The ordinary ending: the phone's session finished, so its answer to the
    /// next reading is no. It is the only ending the phone can reach, which is
    /// why every reading carries a reply.
    @Test("The phone answering no ends the sharing")
    func stopsWhenThePhoneIsDone() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        arrangement.phone.isWanted = false

        try await arrangement.report(61)
        try await settle { arrangement.relay.hasFinished }

        #expect(arrangement.relay.hasFinished)
    }

    /// The backstop, and the reason `start()` exists: a wrist with no read grant
    /// never gets a reading, so nothing would ever carry a reply — and the
    /// workout would run until somebody noticed.
    @Test("A wrist that never gets a reading still stops itself")
    func stopsAfterTheSilenceWithNoReadingsAtAll() async throws {
        let arrangement = arrangement()

        arrangement.relay.start()
        arrangement.clock.advance(by: PulseRelay.silence + .seconds(1))
        try await settle { arrangement.relay.hasFinished }

        #expect(arrangement.relay.hasFinished)
        #expect(arrangement.phone.readings.isEmpty)
    }

    /// The other half of the backstop: a send that never comes back. The reply is
    /// what normally ends this, so a radio waiting out its own timeout would
    /// otherwise leave the wrist sharing with nothing able to stop it.
    @Test("A send that never answers does not keep the wrist sharing")
    func stopsWhileASendHangs() async throws {
        let arrangement = arrangement()
        arrangement.phone.hangs = true
        arrangement.relay.start()

        arrangement.relay.report(61)
        try await settle { !arrangement.phone.readings.isEmpty }
        arrangement.clock.advance(by: PulseRelay.silence + .seconds(1))
        try await settle { arrangement.relay.hasFinished }

        #expect(arrangement.relay.hasFinished)
    }

    /// Every answered reading buys another minute, so an arrangement somebody is
    /// wearing through a half-hour session never trips its own backstop.
    @Test("An answered reading re-arms the silence")
    func answeredReadingsKeepSharingAlive() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        // Two thirds of the way through the silence, twice over: without the
        // re-arming, the second stretch would take the total past the backstop.
        for _ in 0 ..< 2 {
            arrangement.clock.advance(by: .seconds(40))
            try await arrangement.report(61)
            arrangement.clock.advance(by: PulseRelay.spacing)
        }

        #expect(!arrangement.relay.hasFinished)
        #expect(arrangement.phone.readings.count == 2)
    }

    @Test("A stopped relay sends nothing more, however often it is offered")
    func ignoresReadingsAfterStopping() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        arrangement.relay.stop()

        try await arrangement.reportWithoutSending(61)

        #expect(arrangement.phone.readings.isEmpty)
        #expect(arrangement.relay.hasFinished)
    }
}
