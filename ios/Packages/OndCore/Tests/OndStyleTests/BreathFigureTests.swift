import Foundation
import OndKit
@testable import OndStyle
import SwiftUI
import Testing

/// What the figure claims about a breath, measured rather than assumed: it stays
/// inside its own square in every treatment, it only grows on the way in, the
/// four phases read apart without colour, it degrades to scale alone, and it
/// costs nothing at rest.
@Suite("Breath figure")
struct BreathFigureTests {
    /// The unit square is the contract every caller sizes against, so anything
    /// escaping it is a figure clipped at one scale and merely tight at another.
    /// Worth measuring because every asymmetry spends room the symmetric
    /// arrangement had no need for, and they spend it at different moments.
    @Test("nothing any form draws leaves the unit square", arguments: BreathPosing.treatments)
    func figureStaysInsideItsSquare(_ configuration: BreathFigure.Configuration) {
        for breath in BreathPosing.breaths {
            for moment in BreathPosing.moments {
                let posed = BreathPosing.pose(
                    for: breath,
                    at: moment,
                    configuration: configuration,
                    side: .left
                )
                let reaches = posed.rings.map { BreathPosing.square(around: $0) }
                    + posed.vertices.map { max(abs($0.x), abs($0.y)) }
                    + [BreathPosing.square(around: posed.rim)]

                for reach in reaches {
                    #expect(reach <= 0.5, "\(breath) at \(moment) reaches \(reach)")
                }
            }
        }
    }

    /// The breath only ever gets bigger on the way in.
    ///
    /// The regression this pins was invisible to every bound above: under the
    /// `lungs` closure the closed radius was derived from the figure's whole
    /// extent and came out *larger* than the open one, so a place shrank slightly
    /// as the lungs filled while the arrangement around it grew. The envelope was
    /// monotonic throughout, which is what everything else here measures.
    @Test("nothing shrinks as the breath fills", arguments: BreathPosing.treatments)
    func fillingOnlyEverGrows(_ configuration: BreathFigure.Configuration) {
        var envelopes: [CGFloat] = []
        var radii: [CGFloat] = []

        for moment in BreathPosing.moments {
            let posed = BreathPosing.pose(
                for: .inhale(through: .nose),
                at: moment,
                configuration: configuration
            )
            envelopes.append(posed.envelope)
            radii.append(posed.rings.first?.radius ?? 0)
        }

        #expect(envelopes == envelopes.sorted())
        #expect(radii == radii.sorted())
    }

    /// The `lungs` closure exists to stop where the shipped orb stops, so what it
    /// is measured against is the orb's own floor rather than a number of its own.
    @Test("the lungs closure closes to the orb's own floor")
    func lungsClosureMatchesTheOrb() {
        let configuration = BreathFigure.Configuration(closure: .lungs, bias: .centred)
        let empty = BreathPosing.pose(for: .holdOut, at: 0, configuration: configuration).envelope
        let full = BreathPosing.pose(for: .holdIn, at: 0, configuration: configuration).envelope

        #expect(abs(empty / full - SessionTimeline.Beat.emptyLungs) < 1e-9)
    }

    /// The claim the design rests on. Compared as motions rather than as single
    /// frames, because that is what separates the two holds: both are steady, and
    /// one is steady wide while the other is steady tight.
    @Test("every phase draws a different motion", arguments: BreathFigure.Cadence.allCases)
    func phasesAreDistinctWithoutColour(_ cadence: BreathFigure.Cadence) {
        let configuration = BreathFigure.Configuration(cadence: cadence)
        let motions = BreathPosing.breaths.map { breath in
            BreathPosing.moments.map {
                BreathPosing.pose(for: breath, at: $0, configuration: configuration).rings
            }
        }

        for first in motions.indices {
            for second in motions.indices where second > first {
                #expect(motions[first] != motions[second])
            }
        }
    }

    /// A hold moves no air, so a figure keyed to lung fullness alone sits dead
    /// for the length of one — the state the shipped Reduce Motion ring was
    /// written to escape. The turn is what fills it, and that is the whole of the
    /// turn's job.
    @Test("a hold keeps turning", arguments: [Breath.holdIn, .holdOut])
    func holdsNeverFreeze(_ breath: Breath) {
        let start = BreathPosing.pose(for: breath, at: 0)
        let middle = BreathPosing.pose(for: breath, at: 0.5)

        #expect(start.rings != middle.rings)
        #expect(start.vertices != middle.vertices)
        #expect(start.bloom == middle.bloom)
    }

    /// A phase turns a whole number of the arrangement's own symmetry steps,
    /// which is what lets the spin start from zero every phase rather than carry
    /// a running total. Stop this holding and every phase boundary jumps.
    @Test("a phase turns a whole symmetry step", arguments: BreathPosing.treatments)
    func phasesEndSymmetryEquivalent(_ configuration: BreathFigure.Configuration) {
        let step = 360.0 / Double(configuration.ringCount)
        var symmetric = configuration
        symmetric.bias = .centred

        for breath in BreathPosing.breaths {
            let turned = BreathPosing
                .pose(for: breath, at: 1, configuration: configuration)
                .spin.degrees
            #expect((turned / step).remainder(dividingBy: 1).magnitude < 1e-9)
        }

        // And the step really is a symmetry of the arrangement: turning by one
        // lands the places where the previous ones were.
        let before = BreathPosing.pose(bloom: 0.7, spin: .zero, configuration: symmetric)
        let after = BreathPosing.pose(bloom: 0.7, spin: .degrees(step), configuration: symmetric)
        #expect(BreathPosing.rounded(before.rings) == BreathPosing.rounded(after.rings))
    }

    /// Reduce Motion leaves scale and nothing else.
    ///
    /// The quiet forms need nothing done to them — the turn is already zero, so
    /// an aperture simply scales — and the rings, which are the one form built
    /// out of travel, fall back to the arrangement's own envelope as a single
    /// circle. Drawn as the envelope rather than as one of the orbiting circles,
    /// so the figure is the same size with the setting on as with it off and
    /// switching does not resize the screen.
    @Test("Reduce Motion leaves one scaling circle", arguments: BreathPosing.treatments)
    func reduceMotionDegradesToScale(_ configuration: BreathFigure.Configuration) {
        for breath in BreathPosing.breaths {
            var radii: [CGFloat] = []

            for moment in BreathPosing.moments {
                let stilled = BreathPosing.pose(
                    for: breath,
                    at: moment,
                    configuration: configuration,
                    reduceMotion: true
                )

                #expect(stilled.rings.count == 1)
                #expect(stilled.spin == .zero)
                #expect(stilled.rings.first?.centre == .zero)
                radii.append(stilled.rings.first?.radius ?? 0)
            }

            // Only a moving phase has anything left to say once the turn is gone;
            // a hold under Reduce Motion is legitimately still.
            #expect((radii.first != radii.last) == !breath.kind.isHold)
        }
    }

    /// The envelope claim above, exactly: with no asymmetry to spend room on, the
    /// stilled circle is the reach of the moving arrangement.
    @Test("the stilled circle is the moving figure's own envelope")
    func stilledCircleMatchesTheEnvelope() {
        for closure in BreathFigure.Closure.allCases {
            let configuration = BreathFigure.Configuration(closure: closure, bias: .centred)

            for moment in BreathPosing.moments {
                let stilled = BreathPosing.pose(
                    for: .inhale(through: .nose),
                    at: moment,
                    configuration: configuration,
                    reduceMotion: true
                )
                let moving = BreathPosing.pose(
                    for: .inhale(through: .nose),
                    at: moment,
                    configuration: configuration
                )

                #expect(abs((stilled.rings.first?.radius ?? 0) - moving.envelope) < 1e-9)
                #expect(abs(BreathPosing.extent(of: moving) - moving.envelope) < 1e-9)
            }
        }
    }

    /// The prototype's answer to the resting-cost regression. A value comparison
    /// rather than a frame count, which is the part a test can hold: an unchanged
    /// breath poses equal, so SwiftUI drops the redraw and a figure nobody is
    /// breathing to is never re-pathed.
    @Test("an unchanged breath poses identically")
    func restingPoseIsStable() {
        #expect(BreathFigure.seed() == BreathFigure.seed())
        #expect(
            BreathPosing.pose(for: .holdOut, at: 0.5)
                == BreathPosing.pose(for: .holdOut, at: 0.5)
        )
    }

    /// Every phase strokes in an ink the technique drawings already carry, so the
    /// exhale arrives with the softening measured to clear WCAG 1.4.11's 3:1 on
    /// every goal accent in every appearance — and nothing here fades a stroke,
    /// so there is no second measurement to keep in step. The holds share an ink
    /// because they share one in the shipped player too.
    @Test("phases stroke in the technique drawings' own inks")
    func inksAreTheFiguresOwn() {
        #expect(BreathFigure.ink(for: .inhale) == .inhale)
        #expect(BreathFigure.ink(for: .exhale) == .exhale)
        #expect(BreathFigure.ink(for: .holdIn) == .hold)
        #expect(BreathFigure.ink(for: .holdOut) == .hold)
    }
}
