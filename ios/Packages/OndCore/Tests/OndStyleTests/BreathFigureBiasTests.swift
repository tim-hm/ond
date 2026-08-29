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
    /// every one vanishes here without being special-cased — including the vent,
    /// which closes rather than narrowing to a slit.
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
            let reaches = seeded.outline.points.map { hypot($0.x, $0.y) }

            #expect(seeded.outline.isClosed)
            #expect((reaches.max() ?? 0) - (reaches.min() ?? 0) < 1e-9)
            #expect(BreathPosing.weight(of: seeded).magnitude < 1e-9)
        }
    }

    /// The asymmetry is spent in geometry rather than in ink, and this is the
    /// half of that claim a value can carry: a swelled figure is a different
    /// shape from a centred one, weighted the way the air is going.
    @Test("a nostril weights the figure towards its side")
    func nostrilsBendTheFigure() {
        let configuration = BreathFigure.Configuration(bias: .swell)
        let centred = BreathPosing.pose(
            for: .inhale(through: .nose),
            at: 1,
            configuration: configuration
        )
        let left = BreathPosing.biased(configuration, towards: .left)
        let right = BreathPosing.biased(configuration, towards: .right)

        #expect(left.outline != right.outline)
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

    /// The vent, which is the one that reads: the outline stops on the breathing side
    /// and closes all the way round on the other. Three pins, because the gap is only
    /// a nostril if all hold: it faces the right way; it stays put while the
    /// arrangement turns through it, as a mouth fixed to a blade would not; and it is
    /// narrower than one blade — an aperture with an opening rather than an arc.
    @Test("the vent opens on the breathing side", arguments: [3, 6, 8])
    func ventFacesTheBreath(_ places: Int) throws {
        let configuration = BreathFigure.Configuration(places: places, bias: .vent)
        let blade = 2 * Double.pi / Double(places)

        for side in [Passage.Side.left, .right] {
            for moment in [0.5, 0.75, 1.0] {
                let posed = BreathPosing.pose(
                    for: .inhale(through: side == .left ? .leftNostril : .rightNostril),
                    at: moment,
                    configuration: configuration,
                    side: side
                )
                let outline = posed.outline
                let start = try #require(outline.points.first)
                let end = try #require(outline.points.last)

                #expect(!outline.isClosed)
                // At most one place is swallowed: the two lips, plus every
                // corner but the one the gap can reach.
                #expect(outline.points.count >= places + 1)
                #expect(Self.width(from: end, to: start) < blade)
                #expect((start.x + end.x < 0) == (side == .left))
            }
        }
    }

    /// The vent cuts the outline rather than redrawing it, and this is the part no
    /// angle can check: both lips must land *on* the edge they interrupt. Its own
    /// test because `Pose.boundary(at:)` reaches them by the closed form of a regular
    /// polygon, exact only while no bias both vents and tapers. Measured against the
    /// same figure drawn centred, so nothing here restates the formula it checks.
    @Test("the vent's lips sit on the edge they cut", arguments: [3, 6, 8])
    func ventLipsLieOnTheOutline(_ places: Int) throws {
        var configuration = BreathFigure.Configuration(places: places, bias: .vent)

        for moment in [0.5, 0.75, 1.0] {
            configuration.bias = .vent
            let vented = BreathPosing.pose(
                for: .inhale(through: .leftNostril),
                at: moment,
                configuration: configuration,
                side: .left
            )
            configuration.bias = .centred
            let whole = BreathPosing.pose(
                for: .inhale(through: .leftNostril),
                at: moment,
                configuration: configuration,
                side: .left
            )

            for lip in try [
                #require(vented.outline.points.first),
                #require(vented.outline.points.last),
            ] {
                #expect(
                    Self.lies(lip, on: whole.outline.points),
                    "a lip at \(lip) is off the outline at \(moment) with \(places) places"
                )
            }
        }
    }

    /// A nostril must not resize the figure. Size already means how full the
    /// lungs are, and an asymmetry that grew the drawing would be saying two
    /// things with one dimension — so every bias pays for itself out of the reach
    /// it already had.
    @Test("no bias changes how much room the figure takes", arguments: [3, 6, 8])
    func biasesAreExtentNeutral(_ places: Int) {
        for closure in BreathFigure.Closure.allCases {
            let symmetric = BreathFigure.Configuration(
                places: places,
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

    /// The angle swept going forward from one lip of the gap to the other —
    /// the width of the gap itself, since the outline is walked the other way
    /// round. Both `atan2` results are in `(-π, π]`, so the difference only ever
    /// needs one turn adding back.
    private static func width(from end: CGPoint, to start: CGPoint) -> Double {
        let swept = atan2(start.y, start.x) - atan2(end.y, end.x)
        return swept < 0 ? swept + 2 * .pi : swept
    }

    /// Whether a point sits on one of a closed outline's edges — on the line
    /// through it and between its ends, since a point on the extension of an
    /// edge is not on the figure.
    private static func lies(_ point: CGPoint, on outline: [CGPoint]) -> Bool {
        outline.indices.contains { index in
            let from = outline[index]
            let to = outline[(index + 1) % outline.count]
            let cross = (to.x - from.x) * (point.y - from.y)
                - (to.y - from.y) * (point.x - from.x)
            let along = (to.x - from.x) * (point.x - from.x)
                + (to.y - from.y) * (point.y - from.y)
            let length = pow(to.x - from.x, 2) + pow(to.y - from.y, 2)

            return abs(cross) < 1e-9 && along >= -1e-9 && along <= length + 1e-9
        }
    }
}
