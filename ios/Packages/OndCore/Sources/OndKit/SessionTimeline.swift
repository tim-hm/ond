import Foundation

/// The whole plan for one session, laid out on an absolute time axis from t = 0.
///
/// There is no clock inside this type, and that is the point: every question a
/// player asks — which phase is on screen, how far through it, how many cycles
/// are behind you — is a pure function of elapsed time. The animation can ask it
/// once per frame from `TimelineView`, the cue loop can ask it after waking on a
/// `ContinuousClock`, and a test can ask it with no clock at all. Nothing
/// accumulates, so nothing drifts: a late wake-up answers for the time it
/// actually is rather than the time the previous tick expected.
///
/// An open-ended stage is laid out like any other, at the length the catalogue
/// seeds it with — growing by that length each round, because a hold that comes
/// after more of the protocol is one somebody can settle into for longer. The
/// timeline cannot know how long a hold the person ends will actually last, so
/// it does not try: `SessionModel` stops the clock at the hold's start and
/// splices the plan back on at its end. The laid-out length is what the session
/// suggests aiming for, and nothing enforces it.
public struct SessionTimeline: Sendable, Equatable {
    /// One occurrence of a phase, placed at its offset from the start.
    ///
    /// A beat covers `[start, end)`. The half-open interval is what makes the
    /// boundary unambiguous: at exactly `end` the next beat has begun, so a cue
    /// loop that wakes precisely on time fires the arriving phase rather than
    /// the departing one.
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
        /// Zero-based index of the cycle within the stage.
        public let cycle: Int
        /// Zero-based index of the phase within the cycle's pattern.
        public let phase: Int
        /// Whether the person ends this beat rather than the clock. Its
        /// `duration` is then a hold to aim for, never a scheduled one.
        public let isOpenEnded: Bool
        /// Offset from t = 0.
        public let start: Duration
        public let duration: Duration
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

        /// "Breathe in, left nostril" — this beat as VoiceOver should say it.
        ///
        /// The hint rides along whatever the guidance level: wanting a quieter
        /// screen is not the same as hearing nothing.
        public var spokenInstruction: String {
            breath.spokenInstruction
        }

        public var end: Duration {
            start + duration
        }

        /// The length to suggest aiming for, or nil where the clock owns the
        /// beat and there is nothing to aim at.
        ///
        /// A suggestion in both directions: nothing waits for it to elapse, the
        /// button is still the only thing that ends a retention, and ending one
        /// early is an ordinary way to breathe this rather than a missed number.
        public var target: Duration? {
            isOpenEnded ? duration : nil
        }

        /// How far through this beat `elapsed` sits, as 0...1.
        ///
        /// Clamped, so a caller that hands over a time outside the beat gets a
        /// still-renderable value rather than an orb scaled past the screen.
        public func fraction(at elapsed: Duration) -> Double {
            let span = duration.milliseconds
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
        ///
        /// Public because three renderings re-base with it — the phone's orb,
        /// the technique figure, and the haptic swell — and the same expression
        /// written separately is how they come to disagree about where the top
        /// of a breath is.
        public static func level(ofFullness fullness: Double) -> Double {
            min(max((fullness - emptyLungs) / (1 - emptyLungs), 0), 1)
        }

        /// How full the lungs are at `elapsed`, from `emptyLungs` to 1.
        ///
        /// The number both apps draw their breath guide from — the phone scales
        /// an orb with it, the watch a disc — which is why it is arithmetic here
        /// rather than in either view. A shape is a rendering decision; how full
        /// somebody's lungs are at a given instant is not.
        ///
        /// Smoothstepped rather than linear: a breath does not change pace at
        /// its boundaries, and a linear ramp visibly stops dead at the top of an
        /// inhale. The endpoints are `startFullness` and `endFullness` — the
        /// plan's, not the kind's — so a hold holds whatever it was handed and
        /// the sigh's sip climbs its last tenth rather than starting over.
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
    /// The planned length. An open-ended stage contributes its typical hold, so
    /// this is an estimate for any technique that has one.
    public let totalDuration: Duration

    /// Where each cycle ends, ascending. Precomputed because a cycle boundary is
    /// no longer `elapsed / cycleDuration`: stages have different lengths, so
    /// division would count the short stage's cycles across the long one.
    private let cycleEnds: [Duration]

    /// Lays out `rounds` repetitions of `stages`.
    ///
    /// Counts are floored rather than asserted: a session is not worth trapping
    /// over, and a caller that asks for zero rounds gets one. Empty `stages` is
    /// unreachable from the catalogue — `TechniqueRepository` rejects a
    /// stageless technique — and yields an already-finished timeline rather than
    /// an unadvanceable one.
    public init(stages: [Stage], rounds: Int) {
        let rounds = max(rounds, 1)
        var beats: [Beat] = []
        var cycleEnds: [Duration] = []
        var start = Duration.zero
        var level = Self.openingLevel(of: stages)

        for round in 0 ..< rounds {
            for (stageIndex, stage) in stages.enumerated() {
                for cycle in 0 ..< max(stage.cycles, 1) {
                    let levels = BreathRhythm.levels(through: stage.phases, from: level)
                    for (phaseIndex, phase) in stage.phases.enumerated() {
                        let startLevel = phaseIndex == 0 ? level : levels[phaseIndex - 1]
                        let duration = stage.openEnded
                            ? phase.duration * (round + 1)
                            : phase.duration
                        beats.append(
                            Beat(
                                id: beats.count,
                                breath: phase.breath,
                                round: round,
                                stage: stageIndex,
                                cycle: cycle,
                                phase: phaseIndex,
                                isOpenEnded: stage.openEnded,
                                start: start,
                                duration: duration,
                                startFullness: Beat.fullness(of: startLevel),
                                endFullness: Beat.fullness(of: levels[phaseIndex])
                            )
                        )
                        start += duration
                    }
                    level = levels.last ?? level
                    cycleEnds.append(start)
                }
            }
        }

        self.beats = beats
        self.rounds = rounds
        self.cycleEnds = cycleEnds
        totalDuration = start
    }

    /// What the lungs hold as the plan begins. A plan opening on an exhale or
    /// a full hold can only do so with air already in — you exhale what you
    /// inhaled — so those openings start full; everything else starts empty.
    private static func openingLevel(of stages: [Stage]) -> Double {
        switch stages.first?.phases.first?.kind {
        case .exhale, .holdIn: 1
        case .inhale, .holdOut, nil: 0
        }
    }

    /// The session a technique describes, at its curated length.
    public init(technique: Technique, rounds: Int? = nil) {
        self.init(stages: technique.stages, rounds: rounds ?? technique.recommendedRounds)
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
