import Foundation

/// The whole plan for one session on an absolute time axis from t = 0. No
/// clock inside: every question a player asks is a pure function of elapsed
/// time, so nothing accumulates or drifts. An open-ended stage is laid out at
/// its seeded length, growing per round; `SessionModel` stops the clock there
/// and splices the plan back on — the length is a target, never enforced.
public struct SessionTimeline: Sendable, Equatable {
    /// One occurrence of a phase, placed at its offset from the start. A beat
    /// covers `[start, end)`: at exactly `end` the next beat has begun, so a
    /// cue loop that wakes precisely on time fires the arriving phase rather
    /// than the departing one.
    public struct Beat: Sendable, Equatable, Identifiable {
        /// Position in `beats`. Distinguishes two occurrences of the same phase
        /// kind in the same cycle — the physiological sigh's two inhales are one
        /// technique's worth of proof that `kind` alone cannot identify a beat.
        public let id: Int
        /// What the breath does here, and where the air goes with it — carried
        /// whole rather than as a kind, so a player has the nostril to cue
        /// without going back to the technique the timeline was laid out from.
        public let breath: Breath
        /// Zero-based index of the round this beat belongs to.
        public let round: Int
        /// Zero-based index of the stage within the round.
        public let stage: Int

        /// Whether this beat is the first of a stage that follows another —
        /// what a bell is rung on. Carried rather than recomputed by the cue
        /// channel, which would keep a second copy of the plan. False on the
        /// very first beat: that is the session starting, not a stage
        /// changing, and the countdown has already marked it.
        public let opensStage: Bool

        /// Whether this beat carries on the breath before it rather than
        /// reversing it — the sigh's second sip on top of a full inhale. Two
        /// phases of the same `Breath` are indistinguishable from the breath
        /// alone; only the beat knows what came before it.
        public let stacksOnPrevious: Bool

        /// This phase's place in a connected sigh sentence.
        let cueRole: BreathCueRole

        /// Whether this beat also starts a new round — the seam people count.
        /// Every round opens on its first stage, so this is a stage boundary
        /// landing on stage zero; derived because it reads two facts the beat
        /// already carries.
        public var opensRound: Bool {
            opensStage && stage == 0
        }

        /// Zero-based index of the cycle within the stage.
        public let cycle: Int
        /// Zero-based index of the phase within the cycle's pattern.
        public let phase: Int
        /// Whether the person ends this beat rather than the clock. Its
        /// `duration` is then a hold to aim for, never a scheduled one.
        public let isOpenEnded: Bool
        /// Whether the stage this beat belongs to is too quick to count
        /// through — `Stage.isFastRhythm`, carried at layout. A beat's own
        /// length cannot answer it: the sigh's five-second exhale sits in a
        /// stage of sub-second sips, and the rhythm around the beat decides
        /// whether a counter is legible.
        public let isFastRhythm: Bool
        /// Whether the stage around this beat breathes faster than a resting
        /// rate. Never confused with `isFastRhythm`: that is legibility at two
        /// seconds a phase, this is physiology at four seconds a cycle — the
        /// physiological sigh is true there and false here.
        public let breathesFast: Bool
        /// How this beat's breath is shaped, or nil — which is most beats.
        ///
        /// Carried whole from the phase for the reason `breath` is: every
        /// surface that says something about a beat is handed a `Beat` and
        /// nothing else.
        public let manner: Manner?
        /// The tap this beat's table authored for it, already resolved.
        /// Resolved where the plan is laid out rather than at each cue, so an
        /// id this build does not know is reported per stage, not per beat.
        /// `standard` for every seeded phase, which names none, and that is
        /// what a phase derives for itself.
        public let hapticPattern: HapticPattern
        /// Which words this beat is said in — the session's register, stamped
        /// onto every beat at layout. `SessionTimeline.register` is the
        /// authority; the copy earns its byte on reach: every surface that
        /// says a phase is handed a `Beat` and nothing else, and a register
        /// each fetched separately would drift.
        public let register: CopyRegister
        /// Offset from t = 0.
        public let start: Duration
        /// The whole span this beat occupies on the axis — the phase's
        /// authored length, turn gap included. What everything measuring time
        /// rather than motion runs on; `breathing` is the shorter part of it
        /// the breath moves for.
        public let duration: Duration
        /// The stillness borrowed from the end of this phase before the next
        /// boundary. Laid out rather than derived: the next beat decides
        /// whether an ordinary turn or a stacked-breath pause is needed. Zero
        /// for an open-ended hold — the clock does not keep its length, so
        /// there is no span to borrow from.
        public internal(set) var turnGap: Duration
        /// How full the lungs are as this beat begins, `emptyLungs`...1. Laid
        /// out by the timeline across the whole plan rather than derived from
        /// `kind`, which is what lets the sigh's second sip start where the
        /// first breath finished instead of back at empty.
        public let startFullness: Double
        /// How full the lungs are as this beat ends. A hold keeps its start.
        public let endFullness: Double

        public var kind: PhaseKind {
            breath.kind
        }

        /// Where the air goes, or nil for a hold.
        public var passage: Passage? {
            breath.passage
        }

        /// "Breathe in through your left nostril" — this beat as VoiceOver
        /// should say it. The passage rides along whatever the guidance level:
        /// a quieter screen is not the same as hearing nothing. The mouth goes
        /// unsaid — `Breath.spokenAs` sends a mouth breath to the plain cue,
        /// because "through your mouth" arrives when the breath is half taken.
        public var spokenInstruction: String {
            cueRole.spokenInstruction(for: breath, in: register)
        }

        /// "Breathe in" — this beat as the screen shows it, which drops the
        /// passage the spoken form names. Two forms rather than one because the
        /// screen is read at a glance through half-closed eyes and the nostril
        /// is the thing a session says out loud.
        public var instruction: String {
            cueRole.writtenInstruction(for: breath, in: register)
        }

        /// "Through a curled tongue" — the line under the cue, resolved once.
        ///
        /// Built per call rather than stored: it is three properties this beat
        /// already holds, and `BreathHint` is a value with nothing to allocate.
        public var hint: BreathHint {
            BreathHint(manner: manner, breath: breath, breathesFast: breathesFast)
        }

        public var end: Duration {
            start + duration
        }

        /// How long the breath moves for. What every envelope over a phase
        /// runs on: the orb and rings get it through `fraction(at:)`, but the
        /// haptic controllers are handed a length at the boundary and must ask
        /// for this by name — `duration` is the shorter word and the wrong
        /// one, and picking it compiles. A hold absorbs the difference.
        public var breathing: Duration {
            duration - turnGap
        }

        /// The length to suggest aiming for, or nil where the clock owns the
        /// beat. A suggestion in both directions: nothing waits for it to
        /// elapse, the button alone ends a retention, and ending one early is
        /// an ordinary way to breathe this rather than a missed number.
        public var target: Duration? {
            isOpenEnded ? duration : nil
        }

        /// How far through this beat's breath `elapsed` sits, as 0...1.
        /// Measured against `breathing`, not the whole span: it reaches 1 at
        /// `start + breathing` and stays there for the turn gap, leaving
        /// stillness at the top of an inhale instead of reversing it. Clamped,
        /// so a time outside the beat cannot scale an orb past the screen.
        public func fraction(at elapsed: Duration) -> Double {
            let span = breathing.milliseconds
            guard span > 0 else { return 1 }
            let offset = Double(elapsed.milliseconds - start.milliseconds) / Double(span)
            return min(max(offset, 0), 1)
        }

        /// How empty a breath ever looks. Not zero: lungs at rest still hold
        /// air, and a visual that collapsed to a point would say otherwise.
        public static let emptyLungs = 0.45

        /// `level` (0...1, empty to full) mapped onto the visible range.
        static func fullness(of level: Double) -> Double {
            emptyLungs + level * (1 - emptyLungs)
        }

        /// The inverse: a fullness back on the bare 0...1 level scale, clamped.
        /// Public because three renderings re-base with it — the phone's orb,
        /// the technique figure, and the haptic swell — and separate copies
        /// would disagree about where the top of a breath is.
        public static func level(ofFullness fullness: Double) -> Double {
            min(max((fullness - emptyLungs) / (1 - emptyLungs), 0), 1)
        }

        /// How full the lungs are at `elapsed`, from `emptyLungs` to 1.
        /// Arithmetic here rather than in either view: a shape is a rendering
        /// decision, lung fullness is not. Smoothstepped because a linear ramp
        /// visibly stops dead at the top of an inhale. The endpoints are the
        /// plan's, so a hold holds and the sigh's sip climbs its last tenth.
        public func lungFullness(at elapsed: Duration) -> Double {
            let progress = fraction(at: elapsed)
            let eased = progress * progress * (3 - 2 * progress)

            return startFullness + (endFullness - startFullness) * eased
        }

        /// Whole seconds left in this beat, counting down and never below one —
        /// the last second of a phase is still a second of it.
        public func secondsRemaining(at elapsed: Duration) -> Int {
            max(Int((end - elapsed).seconds.rounded(.up)), 1)
        }
    }

    /// Every beat of the session, in play order.
    public let beats: [Beat]
    /// How many times the whole stage list repeats.
    public let rounds: Int
    /// Which words this session speaks. One register for the whole plan — the
    /// route asks once, at the start — so this is where a beat's copy of it
    /// comes from and the only place it is decided.
    public let register: CopyRegister
    /// The planned length. An open-ended stage contributes its typical hold, so
    /// this is an estimate for any technique that has one.
    public let totalDuration: Duration

    /// Whether any beat of this session has something to say under its cue. A
    /// whole-plan fact because it decides a layout: a hint line that came and
    /// went would move the countdown under it every cycle, so the line is
    /// reserved for the whole of a session that hints anywhere. Should every
    /// exercise hint, this should go; `onlySomeExercisesHintAnything` notices.
    public let hintsAnyBeat: Bool

    /// Where each cycle ends, ascending. Precomputed because a cycle boundary is
    /// no longer `elapsed / cycleDuration`: stages have different lengths, so
    /// division would count the short stage's cycles across the long one.
    private let cycleEnds: [Duration]

    /// Lays out `rounds` repetitions of `stages`. Counts are floored rather
    /// than asserted: a session is not worth trapping over, and zero rounds
    /// gets one. Empty `stages` is unreachable from the catalogue and yields
    /// an already-finished timeline rather than an unadvanceable one.
    public init(
        stages: [Stage],
        rounds: Int,
        register: CopyRegister = .plain
    ) {
        let layout = Layout(stages: stages, rounds: rounds, register: register)
        beats = layout.beats
        self.rounds = layout.rounds
        self.register = register
        cycleEnds = layout.cycleEnds
        totalDuration = layout.totalDuration
        hintsAnyBeat = layout.hintsAnyBeat
    }

    /// The session a technique describes, at its curated length.
    public init(technique: Technique, rounds: Int? = nil, register: CopyRegister = .plain) {
        self.init(
            stages: technique.stages,
            rounds: rounds ?? technique.recommendedRounds,
            register: register
        )
    }

    /// The beat covering `elapsed`, or nil once the session has run out.
    ///
    /// Binary search rather than a scan: a Wim Hof-style session is three rounds
    /// of sixty-plus beats, and this runs on every animation frame.
    public func beat(at elapsed: Duration) -> Beat? {
        guard elapsed >= .zero else { return beats.first }
        guard elapsed < totalDuration else { return nil }

        var low = beats.startIndex
        var high = beats.endIndex
        while low < high {
            let middle = low + (high - low) / 2
            if beats[middle].end <= elapsed {
                low = middle + 1
            } else {
                high = middle
            }
        }
        // `elapsed < totalDuration` is `elapsed < beats.last.end`, so the search
        // always lands on a beat rather than past the end.
        return beats[low]
    }

    /// How far through the whole plan `elapsed` sits, as 0...1 — the session
    /// arc's sweep on phone and wrist. The same clock the header's "left"
    /// number subtracts from, so the two cannot disagree. Clamped, and an
    /// estimate wherever `totalDuration` is one: an open-ended stage contributes
    /// its typical hold and the arc waits there until the person releases it.
    public func progress(at elapsed: Duration) -> Double {
        // A plan with no length is finished rather than unstarted — the same
        // reading `beat(at:)` gives it.
        let total = totalDuration.milliseconds
        guard total > 0 else { return 1 }

        return min(1, max(0, Double(elapsed.milliseconds) / Double(total)))
    }

    /// How many cycles are wholly behind `elapsed` — what the summary counts.
    ///
    /// A cycle abandoned three phases in does not count. Someone who stops early
    /// is told what they finished, never what they left.
    public func cyclesCompleted(at elapsed: Duration) -> Int {
        // Counted rather than searched: this answers when a session ends and
        // when a summary draws, not once a frame.
        cycleEnds.count { $0 <= elapsed }
    }

    /// How many inhales are wholly behind `elapsed`.
    ///
    /// Counted per inhale rather than per cycle because the physiological sigh
    /// takes two of them in one cycle, and both are breaths the person took.
    public func breathsCompleted(at elapsed: Duration) -> Int {
        beats.count { $0.kind == .inhale && $0.end <= elapsed }
    }
}
