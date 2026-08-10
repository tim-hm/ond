import Foundation

/// A run of stages that never hold, drawn as one line — lung fullness over time.
///
/// **Slope is the point.** x is duration and y is fullness, so a phase's
/// steepness *is* its length: extended exhale's four-second rise is visibly
/// steeper than its six-second fall, and the asymmetry that names the exercise
/// is stated without a label. This is one construction rather than a library of
/// waveforms — coherent breathing reads as a symmetric sine because its two
/// phases are equal, not because anything here special-cases it.
///
/// Pure geometry: x runs 0...1 across the drawn window, level runs 0 (lungs
/// empty) to 1 (full), or -1...1 when signed. The view maps it to points; this
/// type owns every judgement about what the line shows:
///
/// - **Whole cycles, as many as the window holds.** Slope alone cannot separate
///   coherent breathing from bellows breath — both are one-to-one, so both are
///   symmetric — and the only thing that distinguishes 5½ breaths a minute from
///   twenty fast ones is tempo. Drawing a fixed span of *time* rather than a
///   fixed count of cycles is what puts tempo on the page.
/// - **No phase narrower than `minimumPhaseShare`.** The physiological sigh's
///   0.7-second sip beside its five-second exhale would otherwise render
///   sub-pixel, and the sip is the technique.
/// - **Every segment of an open-ended stage is `dashed`** — its durations
///   describe a typical pass, not a scheduled one, and the line should not
///   promise what the clock will not keep.
/// - **A run of stages shares one axis, in proportion to the time each is on
///   the page.** The Wim Hof protocol's thirty fast breaths and the one deep
///   breath after them are two stages because they repeat different numbers of
///   times, but they are one unbroken piece of breathing — so the deep breath
///   continues the fast ones' line at its own visibly slower pace, rather than
///   sitting beside them as a second drawing that starts again from empty.
public struct BreathRhythm: Sendable, Equatable {
    /// One phase of the line, from `(start, startLevel)` to `(end, endLevel)`.
    public struct Segment: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let startLevel: Double
        public let endLevel: Double
        /// Whether the phase's length is the person's rather than the clock's.
        public let dashed: Bool
        /// Which stage of the run this segment draws, numbered from zero within
        /// the run rather than within the technique.
        public let stage: Int
        /// Which cycle of *that stage* this segment belongs to — so a renderer
        /// can label the first cycle only rather than stamping the same three
        /// words across every repeat. Numbered per stage rather than across the
        /// whole line, or a merged run would label the stage it opens with and
        /// leave every stage after it unnamed.
        public let cycle: Int
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

        /// No default on `stage` or `cycle`: they say which segment this *is*,
        /// and a caller that forgot one would get a segment quietly claiming
        /// the first cycle of the first stage — which is where the labels are
        /// drawn from.
        public init(
            start: Double,
            end: Double,
            startLevel: Double,
            endLevel: Double,
            dashed: Bool,
            stage: Int,
            cycle: Int,
            phase: Phase
        ) {
            self.start = start
            self.end = end
            self.startLevel = startLevel
            self.endLevel = endLevel
            self.dashed = dashed
            self.stage = stage
            self.cycle = cycle
            self.phase = phase
        }
    }

    /// The span of breathing a line draws, when the stage repeats often enough
    /// to fill it.
    ///
    /// Twenty-two seconds is long enough to hold two cycles of the slowest
    /// hold-free exercise in the catalogue (coherent breathing, at eleven
    /// seconds a cycle) and eleven of the fastest (bellows, at two) — so the two
    /// that are geometrically identical are never visually similar.
    private static let window = Duration.seconds(22)

    /// The ceiling on repeats, which trims the fastest exercises back to a
    /// shorter window than ``window`` would give them.
    ///
    /// Six is where a person still reads breaths. Eleven humps inside a 38-point
    /// list row are hatching — a texture that says "many" but no longer says
    /// "breathe like this", and half a dozen carries the tempo just as well
    /// against coherent breathing's two.
    private static let maximumCycles = 6

    /// The floor under one phase's share of a cycle.
    private static let minimumPhaseShare = 0.08

    public let segments: [Segment]
    /// How many cycles of each stage in the run the line draws, in order.
    public let drawn: [Int]
    /// Whether levels run -1...1 about a midline rather than 0...1 above a
    /// baseline. True only where a technique alternates sides.
    public let signed: Bool

    /// How many cycles are on the page altogether.
    public var cycles: Int {
        drawn.reduce(0, +)
    }

    /// How many whole cycles of `stage` fit the window.
    ///
    /// An open-ended stage draws one: there is no clock to fit, and a retention
    /// repeated is not a thing the exercise does.
    private static func cycles(fitting stage: Stage) -> Int {
        guard !stage.openEnded else { return 1 }

        let cycle = max(stage.cycleDuration.seconds, 0.1)
        let fitting = Int((window.seconds / cycle).rounded())
        return min(max(fitting, 1), min(maximumCycles, max(stage.cycles, 1)))
    }

    /// - Parameter stage: the stage to draw one or more cycles of.
    public init(stage: Stage) {
        self.init(stages: [stage])
    }

    /// - Parameter stages: the stages to draw as one line, in play order.
    ///
    /// Which side of the midline each phase sits on is read from the stages here
    /// rather than handed in beside them: the sides are a function of the phases
    /// (`Stage.signedPhases` derives them from the passages), and a caller free
    /// to supply them was a caller free to supply a set that described some
    /// other stage's phases. A run is signed if any stage in it is, and the
    /// unsigned ones then draw above the midline — the side a technique that
    /// never established one belongs on.
    public init(stages: [Stage]) {
        let played = stages.map { stage in
            (
                stage: stage,
                sided: stage.signedPhases,
                repeats: Self.cycles(fitting: stage)
            )
        }
        // x is time, so each stage takes the share of the width that the part of
        // it on the page takes of the time on the page. Nothing else keeps the
        // Wim Hof protocol's four-second breath visibly slower than the
        // one-and-a-half-second ones drawn to its left.
        let seconds = played.map { max($0.stage.cycleDuration.seconds, 0.1) * Double($0.repeats) }
        let span = max(seconds.reduce(0, +), 0.001)

        var segments: [Segment] = []
        var x = 0.0
        var level = 0.0

        for (index, step) in played.enumerated() {
            // One collection carrying both, so no index has to line up with
            // anything.
            let drawn = step.sided?.map { (phase: $0.phase, sign: $0.side.rawValue) }
                ?? step.stage.phases.map { (phase: $0, sign: 1.0) }
            let phases = drawn.map(\.phase)
            let shares = ProportionalShares.of(
                phases.map { max($0.duration.seconds, 0.001) },
                floor: Self.minimumPhaseShare
            )
            let stageWidth = seconds[index] / span

            for cycle in 0 ..< step.repeats {
                for (position, (item, endLevel)) in zip(
                    drawn,
                    Self.levels(through: phases, from: level)
                ).enumerated() {
                    let width = shares[position] / Double(step.repeats) * stageWidth

                    segments.append(Segment(
                        start: x,
                        end: x + width,
                        // Where the last segment finished, always — which is
                        // what keeps a signed line continuous as it changes
                        // side, and what carries the lungs' state across a stage
                        // boundary. The side only ever swaps at empty lungs, so
                        // the join lands on the midline rather than jumping
                        // across it.
                        startLevel: segments.last?.endLevel ?? 0,
                        endLevel: endLevel * item.sign,
                        dashed: step.stage.openEnded,
                        stage: index,
                        cycle: cycle,
                        phase: item.phase
                    ))
                    x += width
                    level = endLevel
                }
            }
        }

        self.segments = segments
        drawn = played.map(\.repeats)
        signed = played.contains { $0.sided != nil }
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
