import Foundation

/// A running session as everything outside the app sees it: one phase, and the
/// window it occupies on the wall clock.
///
/// This is the whole payload of the Live Activity — the Dynamic Island and the
/// lock screen render nothing that is not here — and it is deliberately a plain
/// value with no `ActivityKit` in sight. Two things fall out of that. The
/// arithmetic below runs on the host under test, which is the only way any of it
/// gets covered at all; and the same value can carry a discreet session's phone
/// expression later (TIM-41) without that mode having to learn what an Activity
/// is.
///
/// **Why the wall clock.** A Live Activity is not a live-rendering view. Its
/// content changes only when the app pushes a new one, and a four-second inhale
/// is a faster cadence than that arrangement is designed for. So nothing here is
/// a position — it is an *interval*, and the two SwiftUI elements that
/// interpolate locally between updates (`ProgressView(timerInterval:)` and
/// `Text(timerInterval:)`) animate across it with no update at all. A snapshot
/// that arrives late, or does not arrive, still runs its own phase out honestly
/// rather than freezing part-way through one.
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
    /// Which words this session speaks, carried across the process boundary
    /// with the breath.
    ///
    /// On the per-beat payload rather than on `SessionActivityAttributes`, even
    /// though it is fixed for the session: the widget reads its sentence off
    /// this value, and a register held on the static half would have every one
    /// of those reads reach for two objects to say one thing.
    ///
    /// The compact Dynamic Island is the one reader that does not consult it —
    /// `PhaseKind.shortInstruction` has no playful form, because a playful
    /// phrase has no one-word shape. That region stays plain by design.
    public let register: CopyRegister
    /// Optional so an activity encoded before connected sigh cues still decodes
    /// and falls back to the words its breath already carries.
    private let cueRole: BreathCueRole?
    /// How this breath is shaped, or nil — which is most phases.
    ///
    /// Optional in its own right rather than for the decoding reason below: a
    /// manner is the exception the catalogue makes, so nil is the ordinary
    /// answer and an older payload's silence is indistinguishable from a plain
    /// breath's, which is the correct reading of both.
    private let manner: Manner?
    /// Whether the stage around this phase breathes fast — nil from an activity
    /// encoded before this existed.
    ///
    /// Optional on `cueRole`'s reasoning: an Activity encoded by the previous
    /// build is still on the lock screen after an update, and a non-optional
    /// `Bool` would fail its decode outright rather than losing a word. Read
    /// through `?? false`, so the older payload simply says less.
    ///
    /// Carried rather than derived, because this value holds a `Breath` and not
    /// a `Phase`: what is fast is the cycle, and only the stage knew.
    private let breathesFast: Bool?

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
    /// no end for it — a hold the person finishes, and a stopped session.
    ///
    /// The one thing a surface can animate against without an update, so it is
    /// derived here rather than pattern-matched at each of the places that
    /// sweep a ring or assert on one.
    public var window: ClosedRange<Date>? {
        guard case let .breathing(window) = stance else { return nil }
        return window
    }

    /// When the retention started, or nil where the phase on screen is not one.
    ///
    /// `window`'s twin, derived here for its reason: the lock screen draws a
    /// count up from this instant *and* speaks the same count as the cue's
    /// accessibility value, and two pattern matches for one date is how the
    /// number somebody sees and the number VoiceOver reads come apart.
    public var heldSince: Date? {
        guard case let .holding(since) = stance else { return nil }
        return since
    }

    /// The line the cue leads with — "Breathe in", or "Paused" when nothing is
    /// moving.
    ///
    /// A paused session must not go on naming a phase: the surface would be
    /// asserting a breath nobody is taking, which is the one thing a glance
    /// cue cannot afford to get wrong.
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

    /// "Cooling Breath · Curled tongue" — what is being practised, and how.
    ///
    /// Here rather than in `SessionCueLabel`, on `TechniqueWords.swift`'s
    /// reasoning: `ios/OndActivity/` has no test bundle, so a merge rule written
    /// there is a curation decision nothing checks.
    ///
    /// The glance form, because this is one line beside a cue on a lock screen
    /// and "Cooling Breath · Through a curled tongue" is a caption that wraps.
    ///
    /// Silent while paused, which the passage caption this replaced was not: a
    /// stopped session captioned "Fast and even" asserts a pace nobody is
    /// breathing, which is the same thing `instruction` refuses one property
    /// above.
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
    /// nothing to show — before it has begun, and once it has ended.
    ///
    /// The two clocks are joined here and only here. `SessionModel` measures in
    /// `Duration` from a `ContinuousClock` anchor, because that is what does not
    /// drift; the system needs `Date`s, because that is what it can interpolate
    /// against while the app is not running. Every window below is the beat's
    /// own length placed around `now` — `beat.end - beat.start` regardless of
    /// where `elapsed` sits — so a reading taken slightly late shifts the window
    /// rather than shortening it into an invalid range.
    ///
    /// - Parameters:
    ///   - session: the session being shown. Read on the main actor, like every
    ///     other reader of the model.
    ///   - now: the wall-clock instant the durations are hung off. Named rather
    ///     than defaulted so a test can assert exact dates.
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

        self.init(
            stance: stance,
            breath: beat.breath,
            register: beat.register,
            cueRole: beat.cueRole,
            manner: beat.manner,
            breathesFast: beat.breathesFast
        )
    }
}
