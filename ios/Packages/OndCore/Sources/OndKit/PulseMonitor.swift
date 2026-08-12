import Foundation
import Observation

/// The phone's side of a shared pulse: it asks the wrist to wear the sensor while
/// a session is running, and holds the freshest reading for as long as one is
/// fresh.
///
/// The arrangement is the wrist's to keep and the phone's to arrange. Nothing here
/// waits, reports or explains — a session with a paired watch on somebody's arm
/// shows a heart rate, and one without simply does not. Every way this can fail
/// arrives as the same silence: no watch, no read grant, a wrist out of range, a
/// workout already running on it. `beatsPerMinute` is nil in all of them, and no
/// surface says a word about it.
///
/// **Why it follows the session rather than being told by a screen.** The obvious
/// wiring is `begin()` and `end()` from the session view, and it is wrong here for
/// `SessionActivity`'s reason, which that type states at length: a session with
/// sound deliberately outlives the screen, and a backgrounded app stops evaluating
/// view bodies. An arrangement ended by a view update would therefore *not* end
/// when a session finished in somebody's pocket — and because this phone is woken
/// by each arriving reading, it would keep answering "yes, keep them coming",
/// holding a workout open on their wrist until they next looked at their phone.
/// `withObservationTracking` is a callback on the session's own registrar and
/// fires either way.
///
/// It keeps two things off the same readings, and they have opposite lifetimes
/// on purpose. `beatsPerMinute` is a *rate*, true only while it is arriving — a
/// badge left showing the last number a departing wrist sent would be telling
/// somebody their heart rate is something it stopped being minutes ago, which is
/// why it expires and why this is a model rather than a stored value. `trace` is
/// a *record* of what already happened, which nothing can make untrue and which
/// the summary draws after the arrangement that filled it has ended.
@MainActor
@Observable
public final class PulseMonitor {
    /// What to draw, or nil for nothing to draw — which is most sessions, and is
    /// never an error.
    public private(set) var beatsPerMinute: Int?

    /// Every reading this session's wrist has sent, for the summary to draw once
    /// the breathing is over.
    ///
    /// Deliberately outlives the arrangement that filled it. `beatsPerMinute`
    /// goes when the readings stop, because a rate is only true while it is
    /// arriving; the trace is a record of what already happened and stays until
    /// the screen showing it goes — which is why it is cleared by [`follow(_:)`]
    /// and [`release()`] rather than by `end()`, the one thing a finished
    /// session does call.
    public private(set) var trace = PulseTrace()

    /// When the trace's first reading arrived, which is where its clock starts.
    ///
    /// The first reading rather than the session, because the gap in between is
    /// the wrist waking up and taking a workout — several seconds of nothing
    /// that would draw as a flat lead-in to a line that had not started.
    private var traceStart: ContinuousClock.Instant?

    /// How long a reading stands before it stops being one.
    ///
    /// Two of the wrist's own sends (`PulseRelay.spacing`) and a little over, so a
    /// lost message does not blink the badge, and short enough that a wrist
    /// somebody took off cannot leave a number on screen long enough to be
    /// believed.
    static let staleness: Duration = .seconds(20)

    private let outbox: WatchHandoffOutbox
    private let launcher: any WristLaunching
    private let push: @MainActor () -> Void
    private let clock: any SessionClock

    /// The arrangement in flight, and the id every arriving reading is measured
    /// against. Nil is "this phone is not asking for readings", which is what
    /// makes the reply to the next one a no.
    private var ordered: WatchSessionOrder?
    private var expiry: Task<Void, Never>?

    /// The session this is following, weakly: sessions come and go and this model
    /// lives for the process, so a strong reference here would keep every session
    /// somebody ever breathed.
    private weak var session: SessionModel?

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

    /// Asks for the grant a launch will need, so the sheet is not somebody's
    /// first breath. Called from the switch that turns the feature on; see
    /// `WristLaunching.prepare()`.
    public func prepare() async {
        await launcher.prepare()
    }

    /// Ties the arrangement to one session's life: arranged while it is being
    /// breathed, ended the moment it is not.
    ///
    /// Called once per session, by the screen that composed it, and only where the
    /// person asked for a heart rate. A paused session ends the arrangement like a
    /// finished one does — the wrist should not hold a workout open for a session
    /// nobody is breathing — and resuming arranges a fresh one.
    public func follow(_ session: SessionModel) {
        self.session = session
        // A new session draws its own line. Cleared here as well as on the way
        // out, because a screen that never disappeared — a second session opened
        // over the first — would otherwise start with the last one's readings.
        forgetTrace()
        observe()
        answer(to: session.status)
    }

    /// Ends the arrangement and stops following. The screen's backstop, for the
    /// departures a status never reports: a session dismissed before it began, or
    /// one whose screen went while it was still waiting to be asked.
    public func release() {
        session = nil
        end()
        // The screen holding the drawing has gone, so the readings behind it go
        // with it. Health data kept past the surface that needed it is storage
        // by another name, which is the promise this feature is built on.
        forgetTrace()
    }

    /// The wrist's answer to a sharing order.
    ///
    /// Only a no is worth acting on, and acting on it is what this exists for: a
    /// wrist that declines — because somebody is breathing a session on it, or it
    /// is already sharing under an older order — leaves this phone holding an
    /// arrangement nothing will ever answer. Ended here, the next session can
    /// arrange again; left standing, no session for the rest of the launch would
    /// ever show a badge.
    public func acknowledge(_ ack: WatchOrderAck) {
        guard let ordered, ack.orderId == ordered.id, !ack.accepted else { return }
        end()
    }

    /// Takes one reading off the radio, and answers whether more are wanted.
    ///
    /// - Returns: false for a phone with nothing arranged and for a reading shared
    ///   under some other order — a wrist finishing with the arrangement a
    ///   previous session made. Either way the wrist stops, which is the only
    ///   thing the phone can usefully say from here. The answer is the contract,
    ///   so it is not discardable.
    public func receive(_ pulse: WatchPulse) -> Bool {
        guard let ordered, pulse.orderId == ordered.id else { return false }

        // Read once: the anchor and the reading it measures have to be the same
        // instant, or the first reading of every session lands a few hundred
        // nanoseconds after the start it defines rather than on it.
        let now = clock.now

        // Assigned only on a change: `@Observable` has no equality check of its
        // own, and the wrist deliberately re-sends an unchanged rate, so an
        // unguarded store would redraw the session screen for news it already has.
        if beatsPerMinute != pulse.beatsPerMinute {
            beatsPerMinute = pulse.beatsPerMinute
        }

        // Recorded whether or not it changed the badge, and that is the point:
        // the wrist re-sending an unchanged rate is a heart that held steady for
        // another `PulseRelay.spacing`, which the line has to show as that much
        // level rather than as a gap it draws straight through.
        let start = traceStart ?? now
        traceStart = start
        trace.append(
            PulseReading(
                elapsed: start.duration(to: now),
                beatsPerMinute: pulse.beatsPerMinute
            )
        )

        let deadline = now.advanced(by: Self.staleness)
        expiry?.cancel()
        expiry = Task {
            try? await clock.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            beatsPerMinute = nil
        }
        return true
    }

    /// Re-arms on every change to the session's status. One-shot, like
    /// `SessionActivity`'s, so the callback re-arms itself — and the hop through a
    /// `Task` is not optional: the callback runs *before* the property changes,
    /// and reading the model from inside it would answer for the state being left.
    private func observe() {
        guard let session else { return }
        withObservationTracking {
            _ = session.status
        } onChange: { [weak self] in
            Task { @MainActor in self?.sessionChanged() }
        }
    }

    private func sessionChanged() {
        guard let session else { return }
        answer(to: session.status)
        // Nothing left to arm once it has finished, and nothing left to arrange.
        if session.status == .finished {
            self.session = nil
        } else {
            observe()
        }
    }

    /// The arrangement follows the breathing: a session being breathed wants a
    /// wrist, and anything else does not. `ready` is the countdown, where the
    /// arrangement has usually already been made — the wrist takes a few seconds
    /// to wake, so waiting for the first breath would cost the badge the opening
    /// of every session.
    private func answer(to status: SessionModel.Status) {
        switch status {
        case .ready, .running, .holding:
            begin()

        case .paused, .finished:
            end()
        }
    }

    /// Asks the wrist to start sharing. A second call while one is arranged is a
    /// no-op.
    ///
    /// The context goes before the launch, because the launch says nothing: it
    /// wakes the watch app, which then reads why from the last thing this phone
    /// said. A refused launch retracts the order rather than leaving it standing —
    /// there is no wrist coming, and a spent errand in the context is one every
    /// later push carries.
    private func begin() {
        guard ordered == nil else { return }

        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)
        ordered = order
        outbox.place(order)
        push()

        // Unheld, deliberately. The launch call cannot be cancelled, so a handle
        // would buy nothing that the guard below does not: an arrangement that
        // ended while this was in flight leaves nothing whose id still matches.
        Task {
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
    private func end() {
        if let ordered {
            outbox.withdraw(ordered.id)
            push()
        }
        ordered = nil
        beatsPerMinute = nil
        expiry?.cancel()
        expiry = nil
    }

    private func forgetTrace() {
        trace = PulseTrace()
        traceStart = nil
    }
}
