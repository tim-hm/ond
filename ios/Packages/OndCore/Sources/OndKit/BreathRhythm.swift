import Foundation

/// One cycle of a stage drawn as a line — lung fullness over time, x 0...1
/// across the cycle, level 0 (empty) to 1 (full). Slope *is* pace, and one
/// construction with no special cases lets a written exercise draw itself by
/// the seeded nine's arithmetic. No phase drops under `minimumPhaseShare` —
/// the sigh's sip is the technique — and an open-ended stage draws dashed.
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
    /// durations describe a typical pass rather than a scheduled one. On the
    /// rhythm rather than each segment: the clock either owns this stage's
    /// lengths or it does not.
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

    /// The level each phase ends at, 0 (empty) to 1 (full). A run of same-kind
    /// breaths — the sigh's second sip — ends on a top-up: the last breath
    /// covers the final ``sipShare`` of the travel, the rest split by time.
    /// Internal because `SessionTimeline` lays beats out with the same
    /// arithmetic — the drawn sigh and the breathed one must agree.
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
