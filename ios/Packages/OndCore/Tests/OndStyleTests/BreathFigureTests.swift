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
    @Test("nothing the figure draws leaves the unit square", arguments: BreathPosing.treatments)
    func figureStaysInsideItsSquare(_ configuration: BreathFigure.Configuration) {
        for breath in BreathPosing.breaths {
            for moment in BreathPosing.moments {
                let posed = BreathPosing.pose(
                    for: breath,
                    at: moment,
                    configuration: configuration,
                    side: .left
                )
                let reach = BreathPosing.square(of: posed)

                #expect(reach <= 0.5, "\(breath) at \(moment) reaches \(reach)")
            }
        }
    }

    /// The breath only ever gets bigger on the way in, and the outline reaches
    /// exactly as far as the envelope every caller sizes against.
    @Test("nothing shrinks as the breath fills", arguments: BreathPosing.treatments)
    func fillingOnlyEverGrows(_ configuration: BreathFigure.Configuration) {
        var envelopes: [CGFloat] = []

        for moment in BreathPosing.moments {
            let posed = BreathPosing.pose(
                for: .inhale(through: .nose),
                at: moment,
                configuration: configuration
            )
            envelopes.append(posed.envelope)

            #expect(abs(BreathPosing.extent(of: posed) - posed.envelope) < 1e-9)
        }

        #expect(envelopes == envelopes.sorted())
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
                BreathPosing.pose(for: breath, at: $0, configuration: configuration).outline
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

        #expect(start.outline != middle.outline)
        #expect(start.bloom == middle.bloom)
    }

    /// A phase turns a whole number of the arrangement's own symmetry steps,
    /// which is what lets the spin start from zero every phase rather than carry
    /// a running total. Stop this holding and every phase boundary jumps.
    @Test("a phase turns a whole symmetry step", arguments: BreathPosing.treatments)
    func phasesEndSymmetryEquivalent(_ configuration: BreathFigure.Configuration) {
        let step = 360.0 / Double(configuration.places)
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
        #expect(
            BreathPosing.rounded(before.outline.points)
                == BreathPosing.rounded(after.outline.points)
        )
    }

    /// Reduce Motion leaves scale and nothing else — and takes nothing that was
    /// not motion. The turn is the figure's only travel, so suppressing it is the
    /// whole degradation: the outline stops pivoting and goes on opening and
    /// closing. The half worth pinning is that a nostril survives it — a vented
    /// figure says which side it breathes through with a gap that does not move.
    @Test("Reduce Motion leaves the breath and the nostril", arguments: BreathPosing.treatments)
    func reduceMotionDegradesToScale(_ configuration: BreathFigure.Configuration) {
        for breath in BreathPosing.breaths {
            var envelopes: [CGFloat] = []

            for moment in BreathPosing.moments {
                let stilled = BreathPosing.pose(
                    for: breath,
                    at: moment,
                    configuration: configuration,
                    side: .left,
                    reduceMotion: true
                )

                #expect(stilled.spin == .zero)
                if configuration.bias == .vent, stilled.bloom > 0 {
                    #expect(!stilled.outline.isClosed)
                }
                envelopes.append(stilled.envelope)
            }

            // Only a moving phase has anything left to say once the turn is gone;
            // a hold under Reduce Motion is legitimately still.
            #expect((envelopes.first != envelopes.last) == !breath.kind.isHold)
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
        #expect(TechniqueFigure.Ink(.inhale) == .inhale)
        #expect(TechniqueFigure.Ink(.exhale) == .exhale)
        #expect(TechniqueFigure.Ink(.holdIn) == .hold)
        #expect(TechniqueFigure.Ink(.holdOut) == .hold)
    }
}
