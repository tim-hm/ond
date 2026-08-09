import OndKit

/// One breathing pattern on repeat, for looking at.
///
/// Built on the real `SessionTimeline` rather than on a hand-rolled clock, so
/// the gallery is driven by the same beats, the same lung curve and the same
/// `signedPhases` a session is. A demonstration that computed its own easing
/// would be a demonstration of something the app does not do.
struct BreathLoop {
    let timeline: SessionTimeline
    /// The side of the midline each phase of the pattern is drawn on, or nil
    /// where this pattern has no nostrils to alternate between.
    private let sides: [Passage.Side]?

    init(_ stage: Stage) {
        timeline = SessionTimeline(stages: [stage], rounds: 1)
        sides = stage.signedPhases?.map(\.side)
    }

    /// Everything a figure needs about one instant of the loop, with the wrapping
    /// done once here — the beat and the numbers read off it have to agree about
    /// what time it is, and they only do if one place decides.
    struct Moment {
        let beat: SessionTimeline.Beat
        /// `SessionTimeline.Beat.lungFullness`, which is what the shipped orb
        /// scales by.
        let fullness: Double
        /// How far through the phase, 0...1.
        let progress: Double
        /// Which nostril the figure leans towards, or nil where there is none.
        let side: Passage.Side?
    }

    /// The loop at `elapsed`, wrapped so the pattern runs forever.
    func moment(at elapsed: Duration, reading: SideReading = .breath) -> Moment? {
        let total = timeline.totalDuration.seconds
        guard total > 0 else { return nil }

        let wrapped = Duration.seconds(elapsed.seconds.truncatingRemainder(dividingBy: total))
        guard let beat = timeline.beat(at: wrapped) else { return nil }

        return Moment(
            beat: beat,
            fullness: beat.lungFullness(at: wrapped),
            progress: beat.fraction(at: wrapped),
            side: side(during: beat, reading: reading)
        )
    }

    /// Which nostril the figure leans towards during `beat`.
    ///
    /// Two answers, and offering both is the point. `.breath` is what the
    /// technique drawings already do: the side comes from the inhale and is
    /// carried through the exhale that empties it, so every crossing happens at
    /// empty lungs. `.passage` reads the phase's own nostril, which is literally
    /// true of the air and sends the figure across the midline at full lungs,
    /// where the breath does not pause.
    private func side(during beat: SessionTimeline.Beat, reading: SideReading) -> Passage.Side? {
        switch reading {
        case .breath:
            guard let sides, sides.indices.contains(beat.phase) else { return nil }
            return sides[beat.phase]
        case .passage:
            return beat.passage?.side
        }
    }

    /// Where the figure takes its side from.
    enum SideReading: String, CaseIterable {
        case breath
        case passage
    }

    /// Box breathing. Four equal phases, so nothing but the motion tells them
    /// apart — the hardest case for the language, and therefore the one to lead
    /// with.
    static let box = BreathLoop(Stage(
        phases: [
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .holdIn, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(4)),
            Phase(kind: .holdOut, duration: .seconds(4)),
        ],
        cycles: 1
    ))

    /// Alternate-nostril breathing, the exercise the passage exists for: in
    /// left, out right, in right, out left.
    static let alternate = BreathLoop(Stage(
        phases: [
            Phase(kind: .inhale, through: .leftNostril, duration: .seconds(4)),
            Phase(kind: .exhale, through: .rightNostril, duration: .seconds(6)),
            Phase(kind: .inhale, through: .rightNostril, duration: .seconds(4)),
            Phase(kind: .exhale, through: .leftNostril, duration: .seconds(6)),
        ],
        cycles: 1
    ))

    /// One phase on its own loop, so all four motions run side by side instead of
    /// being remembered one after another.
    ///
    /// Four stored loops rather than one built on demand: a board asks for these
    /// inside a `TimelineView`, so building one here would lay out a whole
    /// timeline thirty times a second to answer a question whose answer never
    /// changes.
    static func alone(_ kind: PhaseKind) -> BreathLoop {
        switch kind {
        case .inhale: inhaleAlone
        case .holdIn: holdInAlone
        case .exhale: exhaleAlone
        case .holdOut: holdOutAlone
        }
    }

    private static let inhaleAlone = BreathLoop(solo: .inhale)
    private static let holdInAlone = BreathLoop(solo: .holdIn)
    private static let exhaleAlone = BreathLoop(solo: .exhale)
    private static let holdOutAlone = BreathLoop(solo: .holdOut)

    private init(solo kind: PhaseKind) {
        self.init(Stage(phases: [Phase(kind: kind, duration: .seconds(4))], cycles: 1))
    }
}
