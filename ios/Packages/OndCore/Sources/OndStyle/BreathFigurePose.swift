import OndKit
import SwiftUI

/// The arrangement at one instant, and where its places sit.
///
/// Split from `BreathFigure` because the two answer different questions: that
/// file says what the language *is* — the constants, the treatments, the ink —
/// and this one is the arithmetic of a single frame of it.
public extension BreathFigure {
    /// One circle in unit space: a centre offset from the middle of the square,
    /// and a radius, both as fractions of the figure's extent.
    struct Ring: Sendable, Equatable {
        public let centre: CGPoint
        public let radius: CGFloat
    }

    /// The figure at one instant — everything a renderer needs and nothing it has
    /// to ask a clock for.
    ///
    /// `Equatable` and made of scalars on purpose. A pose that has not changed
    /// compares equal, so SwiftUI drops the redraw, and a figure at rest costs
    /// exactly one path that is never rebuilt. The places are computed on demand
    /// rather than stored, so holding a pose allocates nothing.
    ///
    /// Every form reads off the same arrangement: `ringCount` places at evenly
    /// spaced angles, turned by `spin`, reaching `envelope` from the middle, bent
    /// towards a nostril by whichever bias is on. `vertices` and `rim` are that
    /// arrangement for the quiet forms; `rings` is the same one for the elaborate
    /// one. Nothing about a nostril or a scale is decided twice.
    struct Pose: Sendable, Equatable {
        /// 0 at the bottom of the breath, 1 at the top, already eased.
        public let bloom: Double
        /// How far the arrangement has turned within the current phase.
        public let spin: Angle
        /// The nostril the air is going through, or nil where the passage has no
        /// side to it.
        public let side: Passage.Side?
        /// Whether the orbit and the turn are suppressed, leaving the envelope's
        /// scale as the only thing that moves. Set under Reduce Motion.
        public let isStilled: Bool
        public let configuration: Configuration

        /// How far the figure reaches from the middle — its outer edge, and the
        /// same number whichever form draws it and whichever nostril bends it.
        public var envelope: CGFloat {
            let (radius, reach) = span
            return radius + reach
        }

        /// The corners of the aperture, and where a wheel's marks sit.
        ///
        /// A place's own circle taken out to its far edge, which is what makes
        /// the three forms one arrangement rather than three: a nostril bends all
        /// of them the same way, and each is the same size as the others.
        ///
        /// Unaffected by the orbit collapse `rings` does when stilled, because
        /// the reach is what survives that and the reach is all this reads.
        public var vertices: [CGPoint] {
            let (radius, reach) = span
            let lean = lean(within: reach)
            let orbit = reach - abs(lean)

            return angles.map { angle in
                let out = orbit + radius * taper(towards: cos(angle))
                return CGPoint(x: cos(angle) * out + lean, y: sin(angle) * out)
            }
        }

        /// The wheel's rim, and the circle a stilled figure of any form falls back
        /// to. Leaning moves it and shrinks it by the same amount, so it reaches
        /// exactly as far as it did centred.
        public var rim: Ring {
            let (radius, reach) = span
            let lean = lean(within: reach)
            return Ring(centre: CGPoint(x: lean, y: 0), radius: radius + reach - abs(lean))
        }

        /// Where every circle sits, for the form drawn out of circles.
        ///
        /// Stilled, this is the arrangement's own envelope as one circle rather
        /// than a frozen pose: the figure keeps saying how full the lungs are,
        /// which is the part of it that was never the problem, and stops saying it
        /// with anything that travels.
        public var rings: [Ring] {
            guard !isStilled else { return [rim] }

            let (radius, reach) = span
            let lean = lean(within: reach)
            let orbit = reach - abs(lean)

            return angles.map { angle in
                let centre = CGPoint(x: cos(angle) * orbit + lean, y: sin(angle) * orbit)
                return Ring(centre: centre, radius: radius * taper(towards: cos(angle)))
            }
        }

        /// A place's own radius, and how far the arrangement carries it out.
        /// Whatever a bias spends on an offset it takes back off the second, so
        /// the pair always sums to the same envelope.
        private var span: (radius: CGFloat, reach: CGFloat) {
            let closed = configuration.closure.closedRadius
            let floor = BreathFigure.orbitFloor

            return (
                closed + CGFloat(bloom) * (BreathFigure.openRadius - closed),
                floor + CGFloat(bloom) * (BreathFigure.orbit - floor)
            )
        }

        private var angles: [Double] {
            let step = 2 * Double.pi / Double(configuration.ringCount)
            return (0 ..< configuration.ringCount).map { spin.radians + Double($0) * step }
        }

        /// Which way the breathing side lies in screen coordinates, or nil where
        /// there is no side to lean towards.
        ///
        /// The practitioner's left is drawn on the viewer's left. A figure is a
        /// diagram rather than a mirror, and the alternative — mirroring, the way
        /// a class facing a teacher would see it — makes the drawing depend on who
        /// is imagined to be holding the phone.
        private var breathingDirection: CGFloat? {
            switch side {
            case .left: -1
            case .right: 1
            case nil: nil
            }
        }

        /// How far the arrangement's centre sits off the midline, taken out of
        /// `reach` rather than added to it.
        private func lean(within reach: CGFloat) -> CGFloat {
            guard configuration.bias == .lean, let direction = breathingDirection else { return 0 }

            return direction * BreathFigure.leanFraction * reach * CGFloat(bloom)
        }

        /// How much a place lying at `alignment` along the screen's x axis keeps.
        /// Only the half of the arrangement away from the breath gives anything
        /// up, so the asymmetry stays a side rather than a wobble.
        private func taper(towards alignment: Double) -> CGFloat {
            guard configuration.bias == .swell, let direction = breathingDirection else { return 1 }

            let away = max(0, -direction * CGFloat(alignment))
            return 1 - BreathFigure.swellTaper * away * CGFloat(bloom)
        }
    }
}
