import Foundation
import Observation
import os

/// The wrist's side of a shared pulse: how often a reading goes to the phone,
/// and when to stop sharing altogether.
///
/// The sensor offers a reading every few seconds for as long as a workout session
/// is running, and the phone wants a number on a badge — so most of this type is
/// about not sending. The rest is about ending: the wrist has taken a workout
/// budget for somebody else's session, and nothing about that session is visible
/// from here.
///
/// In `OndKit` rather than the watch target for `WristOrderModel`'s reason. The
/// pacing and the two ways this ends are the whole of the logic, none of it can be
/// exercised where it is used, and getting the ending wrong costs a person their
/// battery rather than a redraw.
@MainActor
@Observable
public final class PulseRelay {
    /// The freshest reading the sensor has offered, whether or not it was sent.
    /// The wrist's own screen shows this: it knows its wearer's heart rate even
    /// when it cannot reach their phone, and a screen going blank because a radio
    /// did would be a lie about the sensor.
    public private(set) var beatsPerMinute: Int?

    /// Whether the sharing is over — the phone said it was done, nothing has
    /// answered in a minute, or the person put a stop to it. The screen watches
    /// this, and its going away is what hands the workout budget back.
    public private(set) var hasFinished = false

    private static let logger = Logger(category: "watch-pulse")

    /// The shortest gap between two readings reaching the phone.
    ///
    /// The sensor reports about every five seconds under a workout session, so
    /// this mostly lets each reading through and exists to hold back the bursts —
    /// HealthKit hands over several samples at once often enough. Deliberately
    /// *not* paired with a "skip an unchanged rate" rule, which is the obvious
    /// saving and a trap: a resting heart reads the same whole number for half a
    /// minute at a time, and a phone that heard nothing for half a minute would
    /// drop the badge from a wrist that was working perfectly.
    static let spacing: Duration = .seconds(4)

    /// How long the wrist keeps sharing with nothing coming back before it stops
    /// on its own.
    ///
    /// The backstop for every ending the reply below cannot reach: a phone out of
    /// range, a person who walked away from it, a sensor that stopped offering
    /// readings so there is nothing left to carry a reply. Generous, because a
    /// pocketed phone comes back and this is not the ordinary way sharing ends —
    /// but finite, because the alternative is a workout session running on
    /// somebody's wrist until they notice it.
    static let silence: Duration = .seconds(60)

    private let order: WatchSessionOrder
    private let send: @MainActor (WatchPulse) async -> Bool
    private let clock: any SessionClock

    /// When the last reading went out, sent or dropped. Advanced on a failure
    /// too: a phone that cannot be reached is not a reason to try faster.
    private var lastSent: ContinuousClock.Instant?
    /// The reading in flight. One at a time — a message waiting on the radio is
    /// already the newest thing the phone will hear.
    private var delivering: Task<Void, Never>?
    /// The silence being waited out, re-armed by every answered reading.
    private var patience: Task<Void, Never>?

    /// The one initialiser that names the clock, internal on `SessionModel`'s
    /// terms: outside a test there is one clock a wrist can pace itself against.
    init(
        order: WatchSessionOrder,
        send: @escaping @MainActor (WatchPulse) async -> Bool,
        clock: any SessionClock
    ) {
        self.order = order
        self.send = send
        self.clock = clock
    }

    /// - Parameters:
    ///   - order: the arrangement these readings are shared under.
    ///   - send: hands one reading to the radio and answers whether the phone
    ///     still wants them — false for a refusal and for a message that never
    ///     arrived, which the wrist treats the same way. A closure so this model
    ///     needs nothing from the watch target.
    public convenience init(
        order: WatchSessionOrder,
        send: @escaping @MainActor (WatchPulse) async -> Bool
    ) {
        self.init(order: order, send: send, clock: SystemClock())
    }

    /// Starts sharing, which is mostly starting to wait.
    ///
    /// Called before the first reading rather than left to it, and that is the
    /// load-bearing part: a wrist with no read grant, or with a sensor that never
    /// reports, would otherwise never arm the silence above — and never sharing
    /// anything is exactly the case where nothing else would ever end this.
    public func start() {
        guard !hasFinished else { return }
        waitOutTheSilence()
    }

    /// Offers one reading, which is sent if it is time for one.
    ///
    /// - Parameter beatsPerMinute: what the sensor measured, rounded here to the
    ///   whole beats the badge shows. A rate of zero is the sensor saying it has
    ///   nothing, and is not worth a message.
    public func report(_ beatsPerMinute: Double) {
        guard !hasFinished else { return }

        let rate = Int(beatsPerMinute.rounded())
        guard rate > 0 else { return }
        self.beatsPerMinute = rate

        guard delivering == nil else { return }
        if let lastSent, clock.now < lastSent.advanced(by: Self.spacing) {
            return
        }

        lastSent = clock.now
        delivering = Task { await self.deliver(rate) }
    }

    /// Stops sharing, from whichever side asked. Idempotent, because all three
    /// endings can arrive at once: the phone's refusal, the screen going away,
    /// and the silence running out are one state, not three.
    public func stop() {
        guard !hasFinished else { return }
        hasFinished = true
        patience?.cancel()
        patience = nil
        delivering?.cancel()
        delivering = nil
    }

    private func deliver(_ rate: Int) async {
        let isWanted = await send(WatchPulse(orderId: order.id, beatsPerMinute: rate))
        delivering = nil

        // Checked after the await: the screen may have gone while this reading
        // was on the radio, and a stopped relay must not arm another minute of
        // waiting on the strength of a reply nobody is acting on.
        guard !hasFinished else { return }

        if isWanted {
            waitOutTheSilence()
        } else {
            stop()
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
