import SwiftUI

public extension View {
    /// Puts the palette's ground behind a scrolling screen: a `List` or
    /// `ScrollView` paints its own background — pure black at night — which is
    /// not this palette's. A `List` needs one thing more: rows stay opaque, and
    /// `listRowBackground` only reaches a row from inside the list, so each row
    /// carries `.listRowBackground(.clear)` itself. `lit:` lifts the ground toward the top.
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
    /// falling to `Surface.ground` by `reach` points. Both ends are tokens
    /// `ThemeColorTests` measures every ink against, so lighting a ground
    /// cannot take text below AA. The geometry stays with the calling screen.
    static func groundGlow(from centre: UnitPoint, reach: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [Theme.Surface.lit, Theme.Surface.ground],
            center: centre,
            startRadius: 0,
            endRadius: reach
        )
    }
}
