import Foundation

/// A running session as everything outside the app sees it — the whole
/// payload of the Live Activity, kept a plain value with no `ActivityKit` so
/// the arithmetic runs on the host under test. Nothing here is a position:
/// an Activity redraws only when the app pushes, so each phase travels as a
/// wall-clock *interval* the system's timer views interpolate across locally.
public struct SessionPresence: Sendable, Hashable, Codable {
    /// What owns the phase on screen, and therefore what the surface may
    /// animate against.
    ///
    /// Each case carries exactly the instant its rendering needs, so a view
    /// never has to ask whether the date beside it means anything.
    public enum Stance: Sendable, Hashable, Codable {
        /// The clock owns this phase: it runs across this window, and then the
        /// next phase begins.
        case breathing(ClosedRange<Date>)
        /// The person owns this phase — an open-ended hold, running since this
        /// instant with no end the plan can name.
        case holding(since: Date)
        /// Stopped, by hand or by the app leaving. Nothing moves.
        case paused
    }

    public let stance: Stance
    /// What the breath is doing and where the air goes, carried whole so the
    /// surface has the nostril without going back to the technique.
    public let breath: Breath
    /// Which words this session speaks. On the per-beat payload rather than
    /// on `SessionActivityAttributes`, though fixed for the session: the
    /// widget reads its sentence off this value alone. The compact Dynamic
    /// Island never consults it — that region carries a ring and ``cueWord``
    /// and stays plain by design.
    public let register: CopyRegister
    /// Optional so an activity encoded before connected sigh cues still decodes
    /// and falls back to the words its breath already carries.
    private let cueRole: BreathCueRole?
    /// How this breath is shaped, or nil — which is most phases. Optional in
    /// its own right, not for decoding: nil is the ordinary answer, so an
    /// older payload's silence reads the same as a plain breath's — correctly.
    private let manner: Manner?
    /// Whether the stage around this phase breathes fast. Optional because an
    /// Activity encoded by the previous build survives an update on the lock
    /// screen, and a non-optional `Bool` would fail its decode outright; read
    /// through `?? false`, the older payload simply says less. Carried, not
    /// derived: what is fast is the cycle, and only the stage knew.
    private let breathesFast: Bool?
    /// The finite plan's end while its clock is running. Optional so an
    /// activity encoded before expanded timing shipped still decodes, and nil
    /// whenever an open-ended hold makes the end unknowable.
    public let sessionEndsAt: Date?
    /// A stopped finite plan cannot drive a wall-clock timer, so its remaining
    /// duration travels as milliseconds instead. Private because surfaces
    /// should read ``sessionRemaining`` and never disagree about the unit.
    private let sessionRemainingMilliseconds: Int64?

    /// Whether nothing is moving. Asked by every surface that has a word, a
    /// glyph or a control that differs while stopped, which is all of them.
    public var isPaused: Bool {
        if case .paused = stance {
            true
        } else {
            false
        }
    }

    /// Whether the person is inside a retention they end themselves — the one
    /// phase no control but theirs can advance.
    public var isHolding: Bool {
        if case .holding = stance {
            true
        } else {
            false
        }
    }

    /// The window the phase on screen runs across, or nil where the plan owns
    /// no end for it — a hold the person finishes, and a stopped session. The
    /// one thing a surface can animate against without an update, so derived
    /// here rather than pattern-matched at every place that sweeps a ring.
    public var window: ClosedRange<Date>? {
        guard case let .breathing(window) = stance else { return nil }
        return window
    }

    /// When the retention started, or nil where the phase on screen is not
    /// one. Derived here because the lock screen draws a count up from this
    /// instant *and* speaks it as the cue's accessibility value — two pattern
    /// matches is how the seen and spoken numbers come apart.
    public var heldSince: Date? {
        guard case let .holding(since) = stance else { return nil }
        return since
    }

    /// The whole plan's window on the wall clock, or nil where there is no
    /// honest end — an open-ended hold, and a stopped session. Derived here
    /// because the widget extension has no test bundle. An end is only stored
    /// beside the remainder it was measured from, so a window implies a
    /// remainder — not the reverse: a paused plan keeps only the remainder.
    public var sessionWindow: ClosedRange<Date>? {
        guard let sessionEndsAt, let remaining = sessionRemaining else { return nil }
        return sessionEndsAt.addingTimeInterval(-remaining.seconds) ... sessionEndsAt
    }

    /// How much of a finite plan remains at this snapshot.
    ///
    /// A running presentation uses ``sessionEndsAt`` so the system can count
    /// locally without another push. This value is the frozen counterpart for
    /// a paused session and the accessibility fallback for either state.
    public var sessionRemaining: Duration? {
        sessionRemainingMilliseconds.map(Duration.milliseconds)
    }

    /// The line the cue leads with — "Breathe in", or "Paused" when nothing
    /// is moving. A paused session must not go on naming a phase: the surface
    /// would be asserting a breath nobody is taking.
    public var instruction: String {
        isPaused
            ? "Paused"
            : (cueRole ?? .plain).writtenInstruction(for: breath, in: register)
    }

    /// The same, as VoiceOver should read it — with the nostril, which is what
    /// makes alternate-nostril breathing that exercise rather than a rhythm.
    public var spokenInstruction: String {
        isPaused
            ? "Paused"
            : (cueRole ?? .plain).spokenInstruction(for: breath, in: register)
    }

    /// The phase in one word — "In", "Hold", "Out" — and nil while paused,
    /// where the caller draws a glyph instead. Neither the register nor the
    /// cue role reaches this: they write sentences and the region fits a word.
    /// ``PhaseKind/shortInstruction`` carries the warning about editing those
    /// words.
    public var cueWord: String? {
        isPaused ? nil : breath.kind.shortInstruction
    }

    /// "Cooling Breath · Curled tongue" — what is being practised, and how.
    /// Here rather than in `SessionCueLabel` because `ios/OndActivity/` has no
    /// test bundle, so a merge rule there is checked by nothing. The glance
    /// form, because the full hint wraps beside a lock-screen cue. Silent
    /// while paused: a caption must not assert a pace nobody is breathing.
    public func caption(of techniqueName: String) -> String {
        guard !isPaused,
              let hint = BreathHint(
                  manner: manner,
                  breath: breath,
                  breathesFast: breathesFast ?? false
              ).glance
        else { return techniqueName }
        return "\(techniqueName) · \(hint)"
    }
}

public extension SessionPresence {
    /// How `session` looks from outside the app at `now`, or nil when there is
    /// nothing to show. The two clocks join only here: the model measures
    /// `Duration` from a `ContinuousClock` anchor; the system needs `Date`s.
    /// Each window is the beat's own length placed around `now`, so a late
    /// reading shifts it, never makes it invalid. `now` lets tests assert exact dates.
    @MainActor
    init?(of session: SessionModel, at now: Date) {
        // One reading of the clock, used by everything below: two would place
        // the window against an instant the beat was not read at.
        let elapsed = session.elapsed
        // Before the cue loop's first turn `currentBeat` is still nil, and the
        // Activity is requested in that window — the timeline answers for it,
        // exactly as the progress header does.
        guard let beat = session.currentBeat ?? session.timeline.beat(at: elapsed) else {
            return nil
        }

        let stance: Stance
        switch session.status {
        case .running:
            stance = .breathing(
                now.addingTimeInterval(-(elapsed - beat.start).seconds)
                    ... now.addingTimeInterval((beat.end - elapsed).seconds)
            )

        case .holding:
            // The plan is pinned to the hold's start, so its own clock is the
            // only thing that knows how long the retention has run.
            stance = .holding(since: now.addingTimeInterval(-session.holdElapsed.seconds))

        case .paused:
            stance = .paused

        case .ready, .finished:
            return nil
        }

        let remaining = session.technique.hasOpenEndedStage ? nil : session.remaining
        let sessionEndsAt: Date? = if session.status == .running, let remaining {
            now.addingTimeInterval(remaining.seconds)
        } else {
            nil
        }

        self.init(
            stance: stance,
            breath: beat.breath,
            register: beat.register,
            cueRole: beat.cueRole,
            manner: beat.manner,
            breathesFast: beat.breathesFast,
            sessionEndsAt: sessionEndsAt,
            sessionRemainingMilliseconds: remaining?.milliseconds
        )
    }
}
