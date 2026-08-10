import Foundation

/// One cycle of a stage, drawn as a line — lung fullness over time.
///
/// **Slope is the point.** x is duration and y is fullness, so a phase's
/// steepness *is* its pace: an inhale climbs, a hold runs flat, an exhale falls
/// back to empty, and extended exhale's four-second rise is visibly steeper
/// than its six-second fall. This is one construction rather than a library of
/// waveforms — box breathing reads as a plateau between two equal slopes
/// because its phases are equal, not because anything here special-cases it —
/// and that is what lets an exercise somebody writes draw itself by the same
/// arithmetic as the nine that are seeded.
///
/// One cycle, deliberately. The cycle is the thing a person is deciding whether
/// to breathe; how often it repeats is a fact for the words around the figure.
/// A grammar before this one drew a fixed window of time so that tempo could
/// tell twenty fast breaths from five slow ones, and the window brought with it
/// closed polygons for holds, a signed midline for nostrils, and a merge rule
/// for staged protocols — four grammars for one idea. The nostril rides on the
/// labels now (`in · 4 L`), and the repeat count on the sentence.
///
/// Pure geometry: x runs 0...1 across the cycle, level runs 0 (lungs empty) to
/// 1 (full). The view maps it to points; this type owns every judgement about
/// what the line shows:
///
/// - **No phase narrower than `minimumPhaseShare`.** The physiological sigh's
///   0.7-second sip beside its five-second exhale would otherwise render
///   sub-pixel, and the sip is the technique.
/// - **Every segment of an open-ended stage is `dashed`** — its durations
///   describe a typical pass, not a scheduled one, and the line should not
///   promise what the clock will not keep.
public struct BreathRhythm: Sendable, Equatable {
    /// One phase of the line, from `(start, startLevel)` to `(end, endLevel)`.
    public struct Segment: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let startLevel: Double
        public let endLevel: Double
        /// The phase this segment draws, carried whole rather than as an index
        /// a renderer would have to resolve against a stage it re-supplies —
        /// the parallel-array hazard that let a segment be labelled from some
        /// other stage's phase with nothing failing.
        public let phase: Phase

        /// Derived, not stored, so a segment cannot claim one kind while
        /// carrying a phase of another.
        public var kind: PhaseKind {
            phase.kind
        }

        public init(
            start: Double,
            end: Double,
            startLevel: Double,
            endLevel: Double,
            phase: Phase
        ) {
            self.start = start
            self.end = end
            self.startLevel = startLevel
            self.endLevel = endLevel
            self.phase = phase
        }
    }

    /// The floor under one phase's share of the cycle.
    private static let minimumPhaseShare = 0.08

    public let segments: [Segment]
    /// Whether the whole line draws dashed — an open-ended stage, whose
    /// durations describe a typical pass rather than a scheduled one.
    ///
    /// On the rhythm rather than each segment: the clock either owns this
    /// stage's lengths or it does not, and a per-segment copy of one fact was a
    /// set of bits that could only ever agree.
    public let dashed: Bool

    /// - Parameter stage: the stage to draw one cycle of.
    public init(stage: Stage) {
        let phases = stage.phases
        let shares = ProportionalShares.of(
            phases.map { max($0.duration.seconds, 0.001) },
            floor: Self.minimumPhaseShare
        )

        var segments: [Segment] = []
        var x = 0.0
        let levels = Self.levels(through: phases, from: 0)

        for (index, (phase, endLevel)) in zip(phases, levels).enumerated() {
            let width = shares[index]
            segments.append(Segment(
                start: x,
                end: x + width,
                // Where the last segment finished, always — which is what keeps
                // the line continuous through the sigh's stacked inhales.
                startLevel: segments.last?.endLevel ?? 0,
                endLevel: endLevel,
                phase: phase
            ))
            x += width
        }

        self.segments = segments
        dashed = stage.openEnded
    }

    /// The level each phase ends at, 0 (empty) to 1 (full).
    ///
    /// An inhale climbs to full and an exhale falls to empty; a hold keeps the
    /// level it was handed. A run of consecutive same-kind breaths — the
    /// physiological sigh's second sip of air — ends on a top-up: the run's
    /// last breath covers the final ``sipShare`` of the travel, and the
    /// breaths before it split the rest in proportion to their time. Internal
    /// rather than private because `SessionTimeline` lays its beats out with
    /// the same arithmetic — the drawn sigh and the breathed one must agree.
    static func levels(through phases: [Phase], from start: Double) -> [Double] {
        var result: [Double] = []
        var level = start
        var index = 0

        while index < phases.count {
            let kind = phases[index].kind
            switch kind {
            case .holdIn, .holdOut:
                result.append(level)
                index += 1

            case .inhale, .exhale:
                var run: [Phase] = []
                while index < phases.count, phases[index].kind == kind {
                    run.append(phases[index])
                    index += 1
                }

                let target = kind == .inhale ? 1.0 : 0.0
                let sip = run.count > 1 ? Self.sipShare : 0
                let travel = (target - level) * (1 - sip)
                let mainSeconds = run.dropLast().reduce(0.0) { $0 + $1.duration.seconds }
                var elapsed = 0.0
                for phase in run.dropLast() {
                    elapsed += phase.duration.seconds
                    let share = mainSeconds > 0 ? elapsed / mainSeconds : 1
                    result.append(level + travel * share)
                }
                result.append(target)
                level = target
            }
        }

        return result
    }

    /// The share of a run's travel its last breath covers: the sigh's sip is
    /// the top tenth of a full inhale — a top-up, not half the climb.
    public static let sipShare = 0.1
}
