import OndUI
import SwiftUI

extension View {
    /// The Coach tab's own ground: a radial that lifts towards the top-left
    /// corner and falls to the palette's darkest surface.
    ///
    /// The lit corner is a screen-local hex on `SessionPlayerView`'s terms —
    /// the refresh spec gives it in the dark appearance only, and a token with
    /// one appearance is a token that lies the first time somebody reads it in
    /// the other. The far end is `Surface.ground` itself, which resolves to
    /// exactly the spec's value *because* the tab is forced dark below.
    ///
    /// **Which is what `coachAppearance()` is for.** A fixed dark ground under
    /// ink that resolves per appearance is the defect that made the session
    /// player unreadable in the light appearance, and this modifier assumes
    /// that pairing has already been made by the stack above it.
    func coachGround() -> some View {
        scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RadialGradient(
                    colors: [CoachGround.lit, Theme.Surface.ground],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: 900
                )
                .ignoresSafeArea()
            )
    }

    /// Forces the Coach tab dark, at the one place that covers all of it.
    ///
    /// On the navigation stack rather than on each screen, because the tab
    /// pushes two screens it does not own — the basics and the check-ins, which
    /// ground themselves with `paletteGround()`. Applied per screen, walking
    /// into either of those flipped the appearance mid-tab; applied here, their
    /// own ground resolves to its dark value and they stay part of the room
    /// they were opened from.
    ///
    /// That makes Coach the second surface in the app that does not follow the
    /// system appearance, and unlike the session it is a tab somebody can sit
    /// on. The spec asks for it; whether a permanently dark tab beside four
    /// light ones is right is a design question, and this comment is where the
    /// next reader finds out it was asked.
    func coachAppearance() -> some View {
        environment(\.colorScheme, .dark)
    }
}

/// The corner the Coach ground is lit from, named so the gradient reads as one
/// decision rather than a literal inside it.
enum CoachGround {
    static let lit = Color(red: 0x10 / 255, green: 0x1F / 255, blue: 0x24 / 255)
}
