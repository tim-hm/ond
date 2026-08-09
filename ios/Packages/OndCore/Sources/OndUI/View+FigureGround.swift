import SwiftUI

/// The restored ground, opaque out to the drawing's own edge and dissolving
/// past it.
///
/// The middle stop is the guarantee rather than a taste: after the scale below,
/// `1 / Theme.Wash.clearance` of the gradient's radius lands exactly on the
/// drawing's outermost edge, so raising the clearance softens the fade without
/// ever moving the opaque part inwards.
private let figureGroundStops: [Gradient.Stop] = [
    Gradient.Stop(color: Theme.Surface.ground, location: 0),
    Gradient.Stop(color: Theme.Surface.ground, location: 1 / Theme.Wash.clearance),
    Gradient.Stop(color: Theme.Surface.ground.opacity(0), location: 1),
]

public extension View {
    /// Puts `Theme.Surface.ground` back under a drawing on a screen that wears
    /// `accentGround(_:)`.
    ///
    /// That wash carries two marks above WCAG 1.4.11's 3:1 and a technique
    /// figure needs four — inhale, exhale, hold and baseline — so re-inking is
    /// not a way out: two marks short of four is still short. The way out is to
    /// stop asking the wash to host the drawing, which is all this does. The
    /// wash goes on making the player feel like the goal everywhere except
    /// directly behind the drawing, and the drawing gets back the ground every
    /// ratio in `TechniqueFigure.Ink.colour(on:)` was measured against. The
    /// numbers, and the test that holds them, are in `ThemeColorTests`.
    ///
    /// Takes no size: a background is laid out at the modified view's own
    /// frame, so the patch reads the drawing's extent from the layout rather
    /// than from a number a second caller could get wrong — and getting it
    /// wrong would mean a stroke back on a partial wash, which is the whole
    /// failure this exists to prevent. The scale is what lets the fade spill
    /// past that frame; a gradient reaching beyond its own bounds would simply
    /// be cut off there, leaving the hard edge the fade is for.
    func figureGround() -> some View {
        background(
            EllipticalGradient(stops: figureGroundStops, center: .center)
                .scaleEffect(Theme.Wash.clearance)
        )
    }
}
