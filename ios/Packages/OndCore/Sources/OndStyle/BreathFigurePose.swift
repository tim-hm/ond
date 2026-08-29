import OndKit
import SwiftUI

/// The arrangement at one instant, and the outline it draws.
///
/// Split from `BreathFigure` because the two answer different questions: that
/// file says what the language *is* — the constants, the treatments, the ink —
/// and this one is the arithmetic of a single frame of it.
public extension BreathFigure {
    /// What a stroke follows: the outline's points in drawing order, and whether
    /// it comes back round to the first of them.
    struct Outline: Sendable, Equatable {
        public let points: [CGPoint]
        /// False where `Bias.vent` has left the figure open on the breathing
        /// side.
        public let isClosed: Bool
    }

    /// The figure at one instant — everything a renderer needs and nothing it
    /// has to ask a clock for. `Equatable` scalars on purpose: an unchanged
    /// pose compares equal, so SwiftUI drops the redraw; the outline is
    /// computed on demand, so holding a pose allocates nothing.
    struct Pose: Sendable, Equatable {
        /// 0 at the bottom of the breath, 1 at the top, already eased.
        public let bloom: Double
        /// How far the arrangement has turned within the current phase.
        public let spin: Angle
        /// The nostril the air is going through, or nil where the passage has no
        /// side to it.
        public let side: Passage.Side?
        public let configuration: Configuration

        /// How far the figure reaches from the middle — its outer edge, and the
        /// same number whichever nostril bends it, because every asymmetry here
        /// either pulls a place in or takes a piece of outline away.
        public var envelope: CGFloat {
            let closed = configuration.closure.closedSpread
            return closed + CGFloat(bloom) * (BreathFigure.openSpread - closed)
        }

        /// The drawn figure. One property rather than parts: a vent starts and
        /// ends part-way along an edge, so a caller handed the corners alone
        /// would have to redo that arithmetic.
        public var outline: Outline {
            guard let vent else { return Outline(points: corners, isClosed: true) }

            let exit = vent.middle + vent.half
            let entry = vent.middle - vent.half
            // The gap is under one blade wide, so it swallows at most one
            // corner, and the corners it keeps are a run: walking from the
            // first one past the exit, the loop stops the moment it reaches the
            // entry rather than skipping and carrying on.
            let first = Int(ceil(exit))
            var points = [boundary(at: exit)]
            points.reserveCapacity(configuration.places + 2)

            for place in first ..< first + configuration.places {
                guard Double(place) < entry + Double(configuration.places) else { break }
                points.append(corner(at: place))
            }

            points.append(boundary(at: entry))
            return Outline(points: points, isClosed: false)
        }

        /// The arrangement's places: `places` of them, evenly spaced, turned by
        /// `spin`, each as far out as the envelope less whatever a swell takes
        /// off it.
        private var corners: [CGPoint] {
            (0 ..< configuration.places).map(corner(at:))
        }

        /// One place. The index is free to run past the last of them, because
        /// the angle it names is periodic and the walk around a vent does not
        /// start at zero.
        private func corner(at place: Int) -> CGPoint {
            let angle = spin.radians + Double(place) * step
            let across = cos(angle)
            let out = envelope * taper(towards: across)

            return CGPoint(x: across * out, y: sin(angle) * out)
        }

        /// Where the outline crosses the ray `position` blades round from the
        /// first place. The closed polygon-edge form is exact only because
        /// `swell` and `vent` are exclusive cases of one enum, so the outline
        /// met here is always regular; a bias that both vented and tapered
        /// would need the general intersection back.
        private func boundary(at position: Double) -> CGPoint {
            // How far round the edge the ray falls, measured from the middle of
            // it, where the outline comes closest to the centre.
            let offset = (position - position.rounded(.down) - 0.5) * step
            let reach = envelope * cos(step / 2) / cos(offset)
            let angle = spin.radians + position * step

            return CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
        }

        /// Where the outline is open, in blades round from the first place, or
        /// nil where it closes all the way round. The half-width is half of
        /// `ventSpan` — under a half-blade by construction, the invariant that
        /// keeps the gap inside one blade. It widens with bloom, so the seed
        /// stays symmetric.
        private var vent: (middle: Double, half: Double)? {
            guard configuration.bias == .vent,
                  let direction = breathingDirection else { return nil }

            let half = BreathFigure.ventSpan * bloom / 2
            guard half > 0 else { return nil }

            return (middle: ((direction < 0 ? .pi : 0) - spin.radians) / step, half: half)
        }

        /// The angle one place is turned from the last, in radians.
        private var step: Double {
            2 * Double.pi / Double(configuration.places)
        }

        /// Which way the breathing side lies in screen coordinates, or nil
        /// where there is no side. The practitioner's left is drawn on the
        /// viewer's left: a diagram rather than a mirror, so the drawing does
        /// not depend on who is imagined to be holding the phone.
        private var breathingDirection: CGFloat? {
            switch side {
            case .left: -1
            case .right: 1
            case nil: nil
            }
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
