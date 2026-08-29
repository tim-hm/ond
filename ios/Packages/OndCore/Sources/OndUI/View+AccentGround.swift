import SwiftUI

public extension View {
    /// Grounds a screen in an accent, strongest at the top. The wash goes over
    /// `Theme.Surface.ground`, not whatever the presentation put behind it.
    /// Only `Theme.Ink.primary` is legible on the result — text here carries no
    /// `foregroundStyle`, and hierarchy is size and weight. Only two marks clear
    /// 3:1, and a figure needs four: `figureGround()` puts the ground back first.
    func accentGround(_ accent: Color) -> some View {
        // Expanded first: a screen whose content does not fill the display —
        // the three-second countdown is a small centred stack — would otherwise
        // get a ground the size of that stack and the system's background
        // around it.
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Theme.Surface.ground
                    .overlay(
                        LinearGradient(
                            colors: [
                                accent.opacity(Theme.Wash.strongest),
                                accent.opacity(Theme.Wash.faintest),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            )
    }
}
