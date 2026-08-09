import Foundation
import OndKit
@testable import OndStyle
import SwiftUI

/// The fixtures and the measurements both breath-figure suites work from.
///
/// Shared rather than duplicated because the two suites disagree about nothing:
/// they ask different questions of the same arrangement, and a second copy of
/// `fullness` is a second easing free to drift from the shipped one.
enum BreathPosing {
    /// Every treatment the gallery can put on screen. Small enough to sweep
    /// exhaustively, and the asymmetric ones are exactly where the geometry runs
    /// out of room, so sweeping is cheaper than choosing.
    ///
    /// `Form` is absent on purpose: a form decides how the arrangement is drawn
    /// and nothing about where its places are, so a pose is the same value in all
    /// three and sweeping them would multiply the work by three for nothing.
    static let treatments: [BreathFigure.Configuration] = [3, 6, 8].flatMap { places in
        BreathFigure.Closure.allCases.flatMap { closure in
            BreathFigure.Cadence.allCases.flatMap { cadence in
                BreathFigure.Bias.allCases.map { bias in
                    BreathFigure.Configuration(
                        ringCount: places,
                        closure: closure,
                        cadence: cadence,
                        bias: bias
                    )
                }
            }
        }
    }

    static let breaths: [Breath] = [
        .inhale(through: .leftNostril),
        .holdIn,
        .exhale(through: .rightNostril),
        .holdOut,
    ]

    static let moments: [Double] = [0, 0.25, 0.5, 0.75, 1]

    static func pose(
        for breath: Breath,
        at progress: Double,
        configuration: BreathFigure.Configuration = BreathFigure.Configuration(),
        side: Passage.Side? = nil,
        reduceMotion: Bool = false
    ) -> BreathFigure.Pose {
        BreathFigure.pose(
            for: breath,
            fullness: fullness(of: breath, at: progress),
            progress: progress,
            side: side,
            reduceMotion: reduceMotion,
            configuration: configuration
        )
    }

    /// A pose built straight from its parts, for the questions that are about the
    /// arrangement rather than about a breath — comparing two rotations at one
    /// bloom, which no phase would ever hand over.
    static func pose(
        bloom: Double,
        spin: Angle,
        configuration: BreathFigure.Configuration
    ) -> BreathFigure.Pose {
        BreathFigure.Pose(
            bloom: bloom,
            spin: spin,
            side: nil,
            isStilled: false,
            configuration: configuration
        )
    }

    /// The figure at the top of an inhale through one nostril — the moment every
    /// asymmetry is at its strongest, and therefore the one to measure.
    static func biased(
        _ configuration: BreathFigure.Configuration,
        towards side: Passage.Side
    ) -> BreathFigure.Pose {
        pose(
            for: .inhale(through: side == .left ? .leftNostril : .rightNostril),
            at: 1,
            configuration: configuration,
            side: side
        )
    }

    /// Where the figure's mass sits along the screen's x axis. Negative is the
    /// viewer's left, which is the practitioner's left nostril.
    static func weight(of pose: BreathFigure.Pose) -> CGFloat {
        pose.rings.reduce(0) { $0 + $1.centre.x * $1.radius * $1.radius }
    }

    /// How far the arrangement reaches from the middle, across everything any
    /// form draws — one number, because that is the claim.
    static func extent(of pose: BreathFigure.Pose) -> CGFloat {
        let reaches = pose.rings.map { hypot($0.centre.x, $0.centre.y) + $0.radius }
            + pose.vertices.map { hypot($0.x, $0.y) }
            + [hypot(pose.rim.centre.x, pose.rim.centre.y) + pose.rim.radius]

        return reaches.max() ?? 0
    }

    /// How far a circle reaches along whichever axis it reaches furthest on —
    /// which is what the unit *square* asks, unlike `extent`.
    static func square(around ring: BreathFigure.Ring) -> CGFloat {
        max(abs(ring.centre.x) + ring.radius, abs(ring.centre.y) + ring.radius)
    }

    /// Rings past floating-point noise, so two arrangements a symmetry step apart
    /// compare equal instead of differing in the twelfth decimal.
    static func rounded(_ rings: [BreathFigure.Ring]) -> Set<[Int]> {
        Set(rings.map { ring in
            [ring.centre.x, ring.centre.y, ring.radius].map { Int(($0 * 1e6).rounded()) }
        })
    }

    /// The shipped lung curve, reached through a one-phase timeline rather than
    /// restated here, so the figure's easing cannot drift from the orb's.
    private static func fullness(of breath: Breath, at progress: Double) -> Double {
        let seconds = 4.0
        let timeline = SessionTimeline(
            stages: [Stage(phases: [Phase(breath, duration: .seconds(seconds))], cycles: 1)],
            rounds: 1
        )
        guard let beat = timeline.beats.first else { return SessionTimeline.Beat.emptyLungs }

        return beat.lungFullness(at: .seconds(seconds * progress))
    }
}
