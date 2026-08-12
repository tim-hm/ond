import Foundation
import Observation

/// The phone's side of a shared pulse: it asks the wrist to wear the sensor for
/// this session, and holds the freshest reading for as long as one is fresh.
///
/// The arrangement is the wrist's to keep and the phone's to arrange. Nothing
/// here waits, reports or explains — a session with a paired watch on somebody's
/// arm shows a heart rate, and one without simply does not. Every way this can
/// fail arrives as the same silence: no watch, no read grant, a wrist out of
/// range, a workout already running on it. `beatsPerMinute` is nil in all of
/// them, and no surface says a word about it.
///
/// The freshness is the whole reason this is a model rather than a stored value.
/// A rate is only worth drawing while it is arriving; a badge left showing the
/// last number a departing wrist sent would be telling somebody their heart rate
/// is something it stopped being minutes ago.
@MainActor
@Observable
public final class PulseMonitor {
    /// What to draw, or nil for nothing to draw — which is most sessions, and is
    /// never an error.
    public private(set) var beatsPerMinute: Int?

    /// How long a reading stands before it stops being one.
    ///
    /// Three of the wrist's own sends (`PulseRelay.spacing`), so a lost message
    /// or two does not blink the badge, and short enough that a wrist somebody
    /// took off cannot leave a number on screen long enough to be believed.
    static let staleness: Duration = .seconds(12)

    private let outbox: WatchHandoffOutbox
    private let launcher: any WristLaunching
    private let push: @MainActor () -> Void
    private let clock: any SessionClock

    /// The arrangement in flight, and the id every arriving reading is measured
    /// against. Nil is "this phone is not asking for readings", which is what
    /// makes the reply to the next one a no.
    private var ordered: WatchSessionOrder?
    private var expiry: Task<Void, Never>?
    private var launch: Task<Void, Never>?

    /// The one initialiser that names the clock, internal on `SessionModel`'s
    /// terms: outside a test there is one clock a reading can go stale against.
    init(
        outbox: WatchHandoffOutbox,
        launcher: any WristLaunching,
        push: @escaping @MainActor () -> Void,
        clock: any SessionClock
    ) {
        self.outbox = outbox
        self.launcher = launcher
        self.push = push
        self.clock = clock
    }

    /// - Parameters:
    ///   - outbox: where the order is placed so the context can carry it.
    ///   - launcher: the system's launch call, behind its seam.
    ///   - push: hands the outbox to the radio — the phone's `WatchLink.push`,
    ///     as a closure so this model needs nothing from the app target.
    public convenience init(
        outbox: WatchHandoffOutbox,
        launcher: any WristLaunching,
        push: @escaping @MainActor () -> Void
    ) {
        self.init(outbox: outbox, launcher: launcher, push: push, clock: SystemClock())
    }

    /// Asks the wrist to start sharing. Called as a session starts; a second call
    /// while one is arranged is a no-op.
    ///
    /// The context goes before the launch, because the launch says nothing: it
    /// wakes the watch app, which then reads why from the last thing this phone
    /// said. A refused launch retracts the order rather than leaving it standing —
    /// there is no wrist coming, and a spent errand in the context is one every
    /// later push carries.
    public func begin() {
        guard ordered == nil else { return }

        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)
        ordered = order
        outbox.place(order)
        push()

        launch = Task {
            let launched = await launcher.launchWatchApp()
            guard !launched, ordered?.id == order.id else { return }
            end()
        }
    }

    /// Ends the arrangement: the order comes out of the context, and the next
    /// reading to arrive is answered with a no.
    ///
    /// Both halves matter and they cover different failures. The retraction stops
    /// a wrist that has not opened yet from starting a workout for a session that
    /// is over — `withdraw` alone would not, since the context already delivered
    /// is replayed on the watch's next activation, which is why this pushes. The
    /// cleared arrangement stops a wrist that *is* sharing, on its next reading.
    public func end() {
        if let ordered {
            outbox.withdraw(ordered.id)
            push()
        }
        ordered = nil
        beatsPerMinute = nil
        expiry?.cancel()
        expiry = nil
        launch?.cancel()
        launch = nil
    }

    /// Takes one reading off the radio, and answers whether more are wanted.
    ///
    /// - Returns: false for a phone with nothing arranged and for a reading shared
    ///   under some other order — a wrist finishing with the arrangement a
    ///   previous session made. Either way the wrist stops, which is the only
    ///   thing the phone can usefully say from here.
    @discardableResult
    public func receive(_ pulse: WatchPulse) -> Bool {
        guard let ordered, pulse.orderId == ordered.id else { return false }

        beatsPerMinute = pulse.beatsPerMinute
        let deadline = clock.now.advanced(by: Self.staleness)
        expiry?.cancel()
        expiry = Task {
            try? await clock.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            beatsPerMinute = nil
        }
        return true
    }
}
