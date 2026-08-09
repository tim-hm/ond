import Foundation
import OndKit
@testable import OndStyle
import Testing

/// What the figure claims about a nostril. Its own suite because the asymmetries
/// answer to a rule the rest of the figure does not: they may bend the drawing
/// and they may not resize it, since size is already spoken for.
@Suite("Breath figure nostrils")
struct BreathFigureBiasTests {
    /// The seed is symmetric whichever nostril is next, which is what lets an
    /// Island cue draw a dot and the full figure grow out of that same dot rather
    /// than out of a miniature of its own. Every asymmetry scales with bloom, so
    /// every one vanishes here without being special-cased.
    @Test("the seed is neutral whatever the passage", arguments: [Passage.Side.left, .right])
    func seedIsNeutral(_ side: Passage.Side) {
        for bias in BreathFigure.Bias.allCases {
            let seeded = BreathFigure.pose(
                for: .inhale(through: .leftNostril),
                fullness: SessionTimeline.Beat.emptyLungs,
                progress: 0,
                side: side,
                configuration: BreathFigure.Configuration(bias: bias)
            )

            #expect(Set(seeded.rings.map(\.radius)).count == 1)
            #expect(BreathPosing.weight(of: seeded).magnitude < 1e-9)
        }
    }

    /// The asymmetry is spent in geometry rather than in ink, and this is the
    /// half of that claim a value can carry: a biased figure is a different shape
    /// from a centred one, weighted the way the air is going.
    @Test("a nostril weights the figure towards its side", arguments: [
        BreathFigure.Bias.lean, .swell,
    ])
    func nostrilsBendTheFigure(_ bias: BreathFigure.Bias) {
        let configuration = BreathFigure.Configuration(bias: bias)
        let centred = BreathPosing.pose(
            for: .inhale(through: .nose),
            at: 1,
            configuration: configuration
        )
        let left = BreathPosing.biased(configuration, towards: .left)
        let right = BreathPosing.biased(configuration, towards: .right)

        #expect(left.rings != right.rings)
        #expect(left.vertices != right.vertices)
        #expect(BreathPosing.weight(of: left) < BreathPosing.weight(of: centred))
        #expect(BreathPosing.weight(of: right) > BreathPosing.weight(of: centred))
    }

    /// The turning bias says the side without moving any mass, so it needs its
    /// own measurement: the two nostrils wind opposite ways from the same start,
    /// and no nostril at all winds the way a centred figure does rather than
    /// backwards.
    @Test("the turning bias winds towards its nostril")
    func nostrilsWindTheFigure() {
        let configuration = BreathFigure.Configuration(bias: .spin)
        let left = BreathPosing.biased(configuration, towards: .left)
        let right = BreathPosing.biased(configuration, towards: .right)
        let noseward = BreathPosing.pose(
            for: .inhale(through: .nose),
            at: 1,
            configuration: configuration
        )
        let centred = BreathPosing.pose(
            for: .inhale(through: .nose),
            at: 1,
            configuration: BreathFigure.Configuration(bias: .centred)
        )

        #expect(left.spin.degrees < 0)
        #expect(right.spin.degrees > 0)
        #expect(noseward.spin == centred.spin)
    }

    /// A nostril must not resize the figure. Size already means how full the
    /// lungs are, and an asymmetry that grew the drawing would be saying two
    /// things with one dimension — so every bias pays for itself out of the reach
    /// it already had, in every form.
    @Test("no bias changes how much room the figure takes", arguments: [3, 6, 8])
    func biasesAreExtentNeutral(_ places: Int) {
        for closure in BreathFigure.Closure.allCases {
            let symmetric = BreathFigure.Configuration(
                ringCount: places,
                closure: closure,
                bias: .centred
            )
            let baseline = BreathPosing.extent(of: BreathPosing.biased(symmetric, towards: .left))

            for bias in BreathFigure.Bias.allCases {
                var configuration = symmetric
                configuration.bias = bias

                for side in [Passage.Side.left, .right] {
                    let reach = BreathPosing
                        .extent(of: BreathPosing.biased(configuration, towards: side))
                    #expect(reach <= baseline + 1e-9, "\(bias) on \(side) reaches \(reach)")
                }
            }
        }
    }
}
