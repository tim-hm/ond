import Foundation
import OndKit
import Testing

/// The number both breath guides fall back to under Reduce Motion. Neither
/// `BreathVisual` nor `BreathRing` can be tested directly — both live in app
/// targets, and every suite runs on the host out of `OndCore` — so this pins
/// the property that makes those renderings work: through a hold, phase fill
/// and lung fullness disagree, and only the first is renderable as guidance.
@Suite("Reduce Motion breath guide")
struct ReduceMotionGuideTests {
    @Test(
        "A hold moves the phase fill while lung fullness stands still",
        arguments: [PhaseKind.holdIn, .holdOut]
    )
    func aHoldStillReadsAsProgress(_ kind: PhaseKind) throws {
        let timeline = SessionTimeline(
            stages: [Stage(phases: [Phase(kind: kind, duration: .seconds(4))], cycles: 1)],
            rounds: 1
        )
        let beat = try #require(timeline.beats.first)

        #expect(beat.lungFullness(at: .zero) == beat.lungFullness(at: .seconds(3)))
        #expect(beat.fraction(at: .zero) < beat.fraction(at: .seconds(3)))
    }
}
