import Foundation
@testable import OndKit
import Testing

/// The wrist's pacing, and the four ways it stops sharing.
///
/// Worth pinning because every failure here is invisible where the code runs. Send
/// too often and a wrist somebody is wearing for half an hour loses its afternoon;
/// stop for the wrong reason and the badge dies on one lost message; forget to stop
/// and the wrist holds a workout open for a session that ended, which on a real
/// device looks like nothing at all until the battery says so.
@MainActor
@Suite("Pulse relay")
struct PulseRelayTests {
    /// A phone whose answer the test scripts, counting what actually reached it.
    @MainActor
    private final class Phone {
        private(set) var readings: [Int] = []
        var delivery: PulseDelivery = .wanted
        /// Whether a send simply never comes back — a radio waiting out its own
        /// timeout, which on WatchConnectivity is the best part of a minute.
        var hangs = false

        func send(_ pulse: WatchPulse) async -> PulseDelivery {
            readings.append(pulse.beatsPerMinute)
            while hangs, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            return delivery
        }
    }

    /// A sensor the test feeds by hand, so the relay's own loop is what carries a
    /// reading from the seam to the radio.
    private final class ScriptedSensor: PulseSource, @unchecked Sendable {
        private let stream: AsyncStream<HeartRateSample>
        private let offers: AsyncStream<HeartRateSample>.Continuation

        init() {
            (stream, offers) = AsyncStream.makeStream()
        }

        func offer(_ sample: HeartRateSample) {
            offers.yield(sample)
        }

        func readings() async -> AsyncStream<HeartRateSample> {
            stream
        }
    }

    /// One assembled arrangement: the relay, the phone at the other end, the
    /// sensor feeding it, and the clocks both run on.
    @MainActor
    private struct Arrangement {
        let relay: PulseRelay
        let phone: Phone
        let sensor: ScriptedSensor
        let clock: ManualClock
        /// What the relay believes the time is, for stamping samples.
        let now: () -> Date

        /// Offers a reading and waits for the send it may have started, so the
        /// assertion after it reads a settled relay.
        func report(_ rate: Double) async throws {
            let delivered = phone.readings.count
            relay.report(HeartRateSample(date: now(), beatsPerMinute: rate))
            try await settle { phone.readings.count > delivered }
        }

        /// Offers a reading that should go nowhere, and gives the relay a moment
        /// to prove it. A nap rather than `settle` for `WristLaunchModel`'s
        /// reason: there is no condition to poll for when the expectation is that
        /// nothing happens.
        func reportWithoutSending(_ rate: Double, at date: Date? = nil) async throws {
            relay.report(HeartRateSample(date: date ?? now(), beatsPerMinute: rate))
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func arrangement() -> Arrangement {
        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)
        let clock = ManualClock()
        let phone = Phone()
        let sensor = ScriptedSensor()
        // Fixed rather than `.now`, so a sample's age is the test's to decide.
        let now = Date(timeIntervalSince1970: 1_754_900_000)
        let relay = PulseRelay(
            order: order,
            sensor: sensor,
            send: { [phone] in await phone.send($0) },
            clock: clock,
            now: { now }
        )
        return Arrangement(relay: relay, phone: phone, sensor: sensor, clock: clock, now: { now })
    }

    @Test("The first reading goes out at once, under the order that asked for it")
    func sendsTheFirstReading() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        try await arrangement.report(61.4)

        #expect(arrangement.phone.readings == [61], "rounded to the beats a badge shows")
        #expect(arrangement.relay.beatsPerMinute == 61)
    }

    /// The sensor's own readings reach the phone without a screen in between —
    /// the loop belongs to the relay, because the wrist it runs on is usually down.
    @Test("A reading the sensor offers travels on its own")
    func pumpsTheSensorItself() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        arrangement.sensor.offer(
            HeartRateSample(date: arrangement.now(), beatsPerMinute: 59)
        )
        try await settle { !arrangement.phone.readings.isEmpty }

        #expect(arrangement.phone.readings == [59])
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

    /// Zero is the one that arrives in practice — the sensor saying it has
    /// nothing. The rest are what the guard's shape is for: `Int(_:)` traps on a
    /// non-finite `Double`, nothing between HealthKit and this seam constrains
    /// one, and the crash would land on the main actor mid-session with a
    /// workout budget open, which is why the conversion sits inside the guard
    /// rather than above it. A rate no heart reaches is refused in the same
    /// breath — the phone answers a reading it cannot read with a no, which ends
    /// the sharing, so the wrist is by far the cheaper place to drop one.
    @Test("A sample that is not a heart rate is not a reading")
    func ignoresASampleThatIsNoRate() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        for rate in [Double.nan, .infinity, 9000, 0, 3] {
            arrangement.relay.report(
                HeartRateSample(date: arrangement.now(), beatsPerMinute: rate)
            )
        }
        // One nap for the lot, on `reportWithoutSending`'s reasoning: there is
        // no condition to poll for when the expectation is that nothing happens.
        try await Task.sleep(for: .milliseconds(20))

        #expect(arrangement.phone.readings.isEmpty)
        #expect(arrangement.relay.beatsPerMinute == nil, "and nothing to draw on the wrist either")
    }

    /// What arrives when no workout raised the sampling rate: HealthKit hands over
    /// a batch it has been holding. Relaying one would put a four-minute-old number
    /// on a badge that promises a live one, which is worse than an empty badge.
    @Test("A stale sample is not somebody's heart rate now")
    func ignoresAStaleReading() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()

        try await arrangement.reportWithoutSending(
            61,
            at: arrangement.now().addingTimeInterval(-240)
        )

        #expect(arrangement.phone.readings.isEmpty)
        #expect(arrangement.relay.beatsPerMinute == nil, "and nothing to draw on the wrist either")
    }

    /// The ordinary ending: the phone's session finished, so its answer to the
    /// next reading is no. It is the only ending the phone can reach, which is
    /// why every reading carries a reply.
    @Test("The phone answering no ends the sharing")
    func stopsWhenThePhoneIsDone() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        arrangement.phone.delivery = .refused

        try await arrangement.report(61)
        try await settle { arrangement.relay.hasFinished }

        #expect(arrangement.relay.hasFinished)
    }

    /// The distinction the whole design rests on. A message that never arrived is
    /// a radio, not an answer — read as a refusal, one moment's interference in
    /// another room ended the badge for the rest of a half-hour session.
    @Test("A reading that never arrives is not a refusal")
    func keepsSharingThroughANonDelivery() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        arrangement.phone.delivery = .undelivered

        try await arrangement.report(61)
        arrangement.clock.advance(by: PulseRelay.spacing)
        try await arrangement.report(62)

        #expect(!arrangement.relay.hasFinished, "a wrist keeps trying until the silence gives up")
        #expect(arrangement.phone.readings == [61, 62])
    }

    /// And it does eventually give up: the silence is what a phone that never
    /// comes back finally trips.
    @Test("Readings nothing ever answers stop the sharing after the silence")
    func stopsAfterTheSilenceWithNothingDelivered() async throws {
        let arrangement = arrangement()
        arrangement.relay.start()
        arrangement.phone.delivery = .undelivered
        try await arrangement.report(61)

        arrangement.clock.advance(by: PulseRelay.silence + .seconds(1))
        try await settle { arrangement.relay.hasFinished }

        #expect(arrangement.relay.hasFinished)
    }

    /// The backstop's first job, and the reason `start()` arms it before any
    /// reading: a wrist with no read grant never produces one, so nothing would
    /// ever carry a reply — and the workout would run until somebody noticed.
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

        arrangement.relay.report(HeartRateSample(date: arrangement.now(), beatsPerMinute: 61))
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

    /// What hands the workout budget back, and it must not need a drawn screen:
    /// the wrist is down for most of every arrangement, and SwiftUI evaluates
    /// nothing while it is.
    @Test("Every ending tells whoever holds the workout, exactly once")
    func reportsItsEnding() async throws {
        for ending in ["refused", "silence", "stopped"] {
            let arrangement = arrangement()
            var endings = 0
            arrangement.relay.onFinished = { endings += 1 }
            arrangement.relay.start()

            switch ending {
            case "refused":
                arrangement.phone.delivery = .refused
                try await arrangement.report(61)

            case "silence":
                arrangement.clock.advance(by: PulseRelay.silence + .seconds(1))

            default:
                arrangement.relay.stop()
            }

            try await settle { endings > 0 }
            #expect(endings == 1, "\(ending) reported once")

            arrangement.relay.stop()
            #expect(endings == 1, "and a second stop reports nothing")
        }
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
