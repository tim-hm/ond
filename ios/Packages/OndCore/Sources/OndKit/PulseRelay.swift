import Foundation
import Observation
import os

/// What became of one reading handed to the radio.
///
/// Three cases and not a `Bool`, because the two failures mean opposite things to
/// a wrist. A refusal is the phone saying the session is over, which is the
/// ordinary way sharing ends. A non-delivery is a radio — somebody walked into
/// another room — and the phone may well still want readings when they walk back.
/// Read as one, a moment's interference ended the sharing for good.
public enum PulseDelivery: Sendable, Equatable {
    /// The phone has it and wants more.
    case wanted
    /// The phone answered, and is done.
    case refused
    /// Nothing answered: out of range, a failed send, an unreadable reply.
    case undelivered
}

/// The wrist's side of a shared pulse: what it does with the sensor's readings,
/// how often one goes to the phone, and when to stop sharing altogether.
///
/// The sensor offers a reading every few seconds for as long as a workout session
/// is running, and the phone wants a number on a badge — so most of this type is
/// about not sending. The rest is about ending: the wrist has taken a workout
/// budget for somebody else's session, and nothing about that session is visible
/// from here.
///
/// It owns the sensor loop rather than leaving it to the screen, and hands the
/// budget back through `onFinished` rather than letting a view do it, for one
/// reason that governs the whole file: **the normal posture for this feature is a
/// wrist that is down.** The watch app keeps running under its workout session,
/// but SwiftUI evaluates nothing while the screen is dark — so every ending that
/// depended on a view update would wait for somebody to raise their arm, which is
/// precisely the workout-left-running failure the silence below exists to prevent.
/// `DiscreetSessionView` carries the same finding for the same reason.
@MainActor
@Observable
public final class PulseRelay {
    /// The freshest reading the sensor has offered, whether or not it was sent.
    /// The wrist's own screen shows this: it knows its wearer's heart rate even
    /// when it cannot reach their phone, and a screen going blank because a radio
    /// did would be a lie about the sensor.
    public private(set) var beatsPerMinute: Int?

    /// Whether the sharing is over — the phone said it was done, nothing has
    /// answered in a minute, or the person put a stop to it.
    public private(set) var hasFinished = false

    /// Called once as the sharing ends, however it ended. What hands the workout
    /// budget back, and it hangs here rather than on the screen for the reason in
    /// the note above: the screen may be dark, and a workout nobody released is
    /// this feature's most expensive way to fail.
    public var onFinished: (@MainActor () -> Void)?

    private static let logger = Logger(category: "session-runtime")

    /// The shortest gap between two readings reaching the phone.
    ///
    /// Every send is a message *and* a reply, and each one wakes the phone — so
    /// this is a battery figure on both devices rather than a freshness one. At
    /// eight seconds a settling heart rate is still current to the beat, and the
    /// sensor's own five-second cadence means roughly every other reading travels.
    ///
    /// Deliberately *not* paired with a "skip an unchanged rate" rule, which is
    /// the obvious saving and a trap: a resting heart reads the same whole number
    /// for half a minute at a time, and a phone that heard nothing for half a
    /// minute would drop the badge from a wrist that was working perfectly.
    static let spacing: Duration = .seconds(8)

    /// How long the wrist keeps sharing with nothing coming back before it stops
    /// on its own.
    ///
    /// The backstop for the endings a reply cannot carry: a sensor that stopped
    /// offering readings, a grant nobody gave, a send that hangs, a phone that
    /// went out of range and stayed there. Generous, because a pocketed phone
    /// comes back and this is not the ordinary way sharing ends — but finite,
    /// because the alternative is a workout session running on somebody's wrist
    /// until they notice it.
    static let silence: Duration = .seconds(60)

    private let order: WatchSessionOrder
    private let sensor: any PulseSource
    private let send: @MainActor (WatchPulse) async -> PulseDelivery
    private let clock: any SessionClock
    /// Wall-clock now, for judging how old a sample is. Separate from `clock`
    /// because a sample is stamped with a `Date` and the pacing is measured on a
    /// monotonic one — `HealthContextModel` takes the same pair for the same
    /// reason.
    private let now: @MainActor () -> Date

    /// When the last reading went out, sent or dropped. Advanced on a failure
    /// too: a phone that cannot be reached is not a reason to try faster.
    private var lastSent: ContinuousClock.Instant?
    /// The reading in flight. One at a time — a message waiting on the radio is
    /// already the newest thing the phone will hear.
    private var delivering: Task<Void, Never>?
    /// The silence being waited out, re-armed by every delivered reading.
    private var patience: Task<Void, Never>?
    /// The sensor loop, held so the stream is dropped when sharing ends.
    private var readings: Task<Void, Never>?

    /// The one initialiser that names the clocks, internal on `SessionModel`'s
    /// terms: outside a test there is one clock a wrist can pace itself against.
    init(
        order: WatchSessionOrder,
        sensor: any PulseSource,
        send: @escaping @MainActor (WatchPulse) async -> PulseDelivery,
        clock: any SessionClock,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.order = order
        self.sensor = sensor
        self.send = send
        self.clock = clock
        self.now = now
    }

    /// - Parameters:
    ///   - order: the arrangement these readings are shared under.
    ///   - sensor: where the readings come from, behind its seam.
    ///   - send: hands one reading to the radio and brings back what became of
    ///     it. A closure so this model needs nothing from the watch target.
    public convenience init(
        order: WatchSessionOrder,
        sensor: any PulseSource,
        send: @escaping @MainActor (WatchPulse) async -> PulseDelivery
    ) {
        self.init(order: order, sensor: sensor, send: send, clock: SystemClock())
    }

    /// Starts sharing: opens the sensor, and starts waiting.
    ///
    /// The silence is armed before the first reading rather than after, and that
    /// is the load-bearing part: a wrist with no read grant, or one nobody is
    /// wearing, never produces a reading at all — which is exactly the case where
    /// nothing else would ever end this.
    public func start() {
        guard !hasFinished, readings == nil else { return }

        waitOutTheSilence()
        readings = Task { [sensor] in
            for await sample in await sensor.readings() {
                report(sample)
            }
        }
    }

    /// Stops sharing, from whichever side asked. Idempotent, because all four
    /// endings can arrive at once: the phone's refusal, the silence running out,
    /// the screen going away, and the person tapping Stop are one state, not four.
    public func stop() {
        guard !hasFinished else { return }
        hasFinished = true
        patience?.cancel()
        patience = nil
        delivering?.cancel()
        delivering = nil
        readings?.cancel()
        readings = nil
        onFinished?()
    }

    /// Takes one reading from the sensor, and sends it if it is time for one.
    ///
    /// Internal rather than private so the suite can offer a reading without
    /// driving a stream; `start()` is the only caller that ships.
    func report(_ sample: HeartRateSample) {
        guard !hasFinished else { return }

        // The conversion is inside the guard because `Int(_:)` traps on a
        // non-finite `Double` and nothing between HealthKit and here constrains
        // one — a rounded NaN would crash the wrist mid-session rather than fail
        // the check written to reject it. The band is checked on this side too,
        // for the reason `WatchPulse.plausible` gives. A reading older than two
        // of our own sends is a batch HealthKit had been holding — which is what
        // arrives when no workout session raised the sampling rate — and
        // relaying it would put a four-minute-old number on a badge that
        // promises a live one.
        guard let rate = Int(exactly: sample.beatsPerMinute.rounded()),
              WatchPulse.plausible.contains(rate),
              now().timeIntervalSince(sample.date) < Self.spacing.seconds * 2
        else {
            return
        }

        // Assigned only on a change: `@Observable` has no equality check of its
        // own, and this design deliberately keeps sending an unchanged rate, so
        // an unguarded store would redraw the wrist's screen twelve times a
        // minute to show the same two digits.
        if beatsPerMinute != rate {
            beatsPerMinute = rate
        }

        guard delivering == nil else { return }
        if let lastSent, clock.now < lastSent.advanced(by: Self.spacing) {
            return
        }

        lastSent = clock.now
        delivering = Task { await self.deliver(rate) }
    }

    private func deliver(_ rate: Int) async {
        let delivery = await send(WatchPulse(orderId: order.id, beatsPerMinute: rate))
        delivering = nil

        // Checked after the await: the screen may have gone while this reading
        // was on the radio, and a stopped relay must not arm another minute of
        // waiting on the strength of a reply nobody is acting on.
        guard !hasFinished else { return }

        switch delivery {
        case .wanted:
            waitOutTheSilence()

        case .refused:
            Self.logger.notice("the phone has finished with this arrangement; sharing stops")
            stop()

        case .undelivered:
            // Deliberately not an ending. The phone may be in another room and
            // may come back; the silence above is what eventually gives up, and
            // reading a moment's interference as a refusal would end the sharing
            // for the rest of a session on the strength of one lost message.
            break
        }
    }

    private func waitOutTheSilence() {
        patience?.cancel()
        let deadline = clock.now.advanced(by: Self.silence)
        patience = Task {
            try? await clock.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            Self.logger.notice("nothing has answered a reading in a minute; sharing stops")
            stop()
        }
    }
}
