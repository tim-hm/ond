import SwiftUI

/// The restored ground, opaque out to the drawing's own edge and dissolving
/// past it. The middle stop is the guarantee: after the scale below,
/// `1 / Theme.Wash.clearance` of the radius lands exactly on the drawing's
/// outermost edge, so raising the clearance never moves the opaque part inwards.
private let figureGroundStops: [Gradient.Stop] = [
    Gradient.Stop(color: Theme.Surface.ground, location: 0),
    Gradient.Stop(color: Theme.Surface.ground, location: 1 / Theme.Wash.clearance),
    Gradient.Stop(color: Theme.Surface.ground.opacity(0), location: 1),
]

public extension View {
    /// Puts `Theme.Surface.ground` back under a drawing on a screen wearing
    /// `accentGround(_:)`: that wash carries two marks above 3:1 and a figure
    /// needs four, so re-inking is no way out. Takes no size — a background is
    /// laid out at the view's own frame; the scale is what lets the fade spill
    /// past it, where a gradient beyond its bounds would clip to a hard edge.
    func figureGround() -> some View {
        background(
            EllipticalGradient(stops: figureGroundStops, center: .center)
                .scaleEffect(Theme.Wash.clearance)
        )
    }
}
