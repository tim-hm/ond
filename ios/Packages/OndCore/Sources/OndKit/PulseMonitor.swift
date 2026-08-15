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

    /// Whether this session might show a rate at all, which is a different
    /// question from whether one is arriving.
    ///
    /// What a screen keeps a place for. `beatsPerMinute` comes and goes over a
    /// session — a wrist wakes a few seconds in, and stops the moment it comes
    /// off — so the badge holds its height against that. This one is settled at
    /// `follow(_:wanted:)` and does not move until the screen goes, so a session
    /// with no wrist coming reserves nothing for one: no invisible capsule, and
    /// no gap above the controls that belongs to nothing.
    public private(set) var expectsReadings = false

    /// Every reading this session's wrist has sent, and how long the session
    /// they came from ran — what the summary draws once the breathing is over.
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
    /// `nonisolated` so `PulseTrace` can break a line on the same figure. It is
    /// a constant, and one definition of "the readings have stopped" is what
    /// keeps the blanked badge and the broken line saying the same thing.
    nonisolated static let staleness: Duration = .seconds(20)

    /// The invented readings, while a rehearsal is running. Nil wherever a real
    /// wrist could answer.
    var rehearsal: Task<Void, Never>?

    /// How far into its settle the invented heart has come.
    ///
    /// On the monitor rather than in the task, because a pause cancels the task:
    /// counted there, every resume would start the curve back at seventy-four and
    /// leave the summary drawing a step no heart makes. Reset per session by
    /// `follow(_:wanted:)`, which is also where the trace it feeds is cleared.
    var rehearsedArrivals = 0

    private let outbox: WatchHandoffOutbox
    private let launcher: any WristLaunching
    private let push: @MainActor () -> Void
    let clock: any SessionClock

    /// Whether this monitor invents readings instead of asking a wrist for them.
    ///
    /// Taken rather than compiled in, because *which builds may invent a heart
    /// rate* is the composition root's to answer and nothing this model can see:
    /// a simulator has no watch to pair with and no sensor to read, and the
    /// deterministic UI-test harness runs in a simulator too and wants the
    /// feature off. See `OndAppComposition.wristHandoff`, the one caller that
    /// ever passes true.
    private let rehearsing: Bool

    /// The arrangement in flight, and the id every arriving reading is measured
    /// against. Nil is "this phone is not asking for readings", which is what
    /// makes the reply to the next one a no.
    private var ordered: WatchSessionOrder?

    #if DEBUG
        /// The order the current session placed with the wrist, for the one
        /// caller that has to stand in for a wrist: the App Store screenshot rig.
        ///
        /// Live heart rate is a önd+ feature and so belongs in the set, and a
        /// watch simulator cannot produce a reading — `HKWorkoutSession` on a
        /// simulator has no sensor behind it, so the feature is unphotographable
        /// without something answering in a wrist's place.
        ///
        /// Read-only, and deliberately the *only* thing exposed. Nothing here can
        /// place an order, change one, or invent a session — a stand-in can
        /// answer the order a real session really placed and nothing else, which
        /// is what keeps the resulting screenshot a picture of the shipping path
        /// rather than of a mock. `receive` still does every check it would do
        /// for the radio.
        public var placedOrderId: UUID? {
            ordered?.id
        }
    #endif
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
        clock: any SessionClock,
        rehearsing: Bool = false
    ) {
        self.outbox = outbox
        self.launcher = launcher
        self.push = push
        self.clock = clock
        self.rehearsing = rehearsing
    }

    /// - Parameters:
    ///   - outbox: where the order is placed so the context can carry it.
    ///   - launcher: the system's launch call, behind its seam.
    ///   - push: hands the outbox to the radio — the phone's `WatchLink.push`,
    ///     as a closure so this model needs nothing from the app target.
    ///   - rehearsing: invents readings rather than asking for them; see the
    ///     property. Defaulted false so the honest arrangement is what a caller
    ///     gets by saying nothing.
    public convenience init(
        outbox: WatchHandoffOutbox,
        launcher: any WristLaunching,
        push: @escaping @MainActor () -> Void,
        rehearsing: Bool = false
    ) {
        self.init(
            outbox: outbox,
            launcher: launcher,
            push: push,
            clock: SystemClock(),
            rehearsing: rehearsing
        )
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
    /// Called when the countdown begins, by the screen that composed the session.
    /// An interrupted countdown or a paused session ends the arrangement like a
    /// finished one does — the wrist should not hold a workout open for a session
    /// nobody is breathing — and restarting or resuming arranges a fresh one.
    ///
    /// - Parameter wanted: whether the person asked for a heart rate. Taken and
    ///   answered here rather than at the call site, because a rehearsing monitor
    ///   follows a session either way: the preference is behind the paywall and a
    ///   simulator has no wrist for it to be about, so a screen that asked the
    ///   question itself would have to know that, and every later pulse surface
    ///   would have to remember to.
    public func follow(_ session: SessionModel, wanted: Bool) {
        guard wanted || rehearsing else { return }

        expectsReadings = true
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
        expectsReadings = false
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
        take(pulse.beatsPerMinute)
        return true
    }

    /// Records one reading, whatever brought it — the radio in every build that
    /// has a wrist to hear from, and `rehearse()` in the simulator.
    func take(_ rate: Int) {
        // Read once: the anchor and the reading it measures have to be the same
        // instant, or the first reading of every session lands a few hundred
        // nanoseconds after the start it defines rather than on it.
        let now = clock.now

        // Assigned only on a change: `@Observable` has no equality check of its
        // own, and the wrist deliberately re-sends an unchanged rate, so an
        // unguarded store would redraw the session screen for news it already has.
        if beatsPerMinute != rate {
            beatsPerMinute = rate
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
                beatsPerMinute: rate
            )
        )

        let deadline = now.advanced(by: Self.staleness)
        expiry?.cancel()
        expiry = Task {
            try? await clock.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            beatsPerMinute = nil
        }
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
            closeTrace()
            self.session = nil
        } else {
            observe()
        }
    }

    /// Tells the trace how long the session it recorded actually ran, which is
    /// the width the summary draws it across.
    ///
    /// Here rather than in `end()`, which a pause reaches too: a paused session
    /// has not finished, and fixing the width at the pause would leave a
    /// resumed session's readings drawn past the end of their own chart.
    private func closeTrace() {
        guard let traceStart else { return }
        trace.close(at: traceStart.duration(to: clock.now))
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
    ///
    /// An order the outbox will not carry — the pairing is part of önd+ — ends
    /// it here, before the watch app is woken for a reading nothing would
    /// deliver. Silently, which is this feature's contract with an unpaired
    /// wrist too: the badge simply does not appear, and what says why is the
    /// Settings row that offers the subscription.
    private func begin() {
        guard ordered == nil else { return }

        // A rehearsal *is* the arrangement: there is no wrist to order and no
        // watch app a launch could wake, so the real path would only fail back to
        // `end()` and leave the badge blank for the whole session. It returns
        // before `ordered` is assigned, so the guard above never catches a second
        // call on this path — `rehearse()` catches it instead.
        if rehearsing {
            rehearse()
            return
        }

        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)
        guard outbox.place(order) else { return }

        ordered = order
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
        rehearsal?.cancel()
        rehearsal = nil
    }

    private func forgetTrace() {
        trace = PulseTrace()
        traceStart = nil
        rehearsedArrivals = 0
    }
}
