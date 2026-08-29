import SwiftUI

public extension View {
    /// Puts the palette's ground behind a scrolling screen, in place of the
    /// system's.
    ///
    /// A `List` or `ScrollView` paints its own background — white in the light
    /// appearance, pure black in the dark one. Pure black is not this palette's
    /// ground, and a screen that keeps it reads as a different app from the one
    /// the session player draws. Hiding the scroll background and putting
    /// `Theme.Surface.ground` under it is what makes them agree.
    ///
    /// A `List` needs one thing more: its rows stay opaque once the scroll
    /// background is hidden, and `listRowBackground` only reaches a row from
    /// inside the list, so the row itself carries `.listRowBackground(.clear)`.
    ///
    /// - Parameter lit: draws the ground lifting toward the top edge instead
    ///   of flat, for a screen whose weight is its opening words. Lit from the
    ///   middle of that edge and spent by the middle of the screen, so the
    ///   glow is behind the title and gone by the time a list starts.
    func paletteGround(lit: Bool = false) -> some View {
        scrollContentBackground(.hidden)
            // Expanded first, because a screen's empty and failed states are a
            // spinner and a message — and a background painted behind those
            // alone would ground a rectangle in the middle of a system-black
            // screen instead of the screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Erased to one style rather than branched as two views: the style
            // overload fills the safe areas for free, which a glow needs — it
            // is brightest at the top edge, and one that stopped under the
            // status bar would draw a hard line across it.
            .background(
                lit
                    ? AnyShapeStyle(RadialGradient.groundGlow(
                        from: UnitPoint(x: 0.5, y: 0),
                        reach: 500
                    ))
                    : AnyShapeStyle(Theme.Surface.ground)
            )
    }
}

public extension RadialGradient {
    /// The lift a ground takes toward one corner: `Surface.lit` at `centre`,
    /// falling to `Surface.ground` by `reach` points.
    ///
    /// Both ends are catalogue tokens `ThemeColorTests` measures every ink
    /// against, so lighting a ground cannot take text below AA in either
    /// appearance. The geometry stays with the screen that asks for it, because
    /// a glow answers to where that screen's words are.
    static func groundGlow(from centre: UnitPoint, reach: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [Theme.Surface.lit, Theme.Surface.ground],
            center: centre,
            startRadius: 0,
            endRadius: reach
        )
    }
}
