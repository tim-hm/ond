import OndUI
import SwiftUI

extension View {
    /// The Coach tab's own ground: a radial that lifts towards the top-left
    /// corner and falls to the palette's base surface.
    ///
    /// Both ends are tokens now, so the tab follows the system appearance like
    /// the other four. It used to force itself dark and take the lit corner
    /// from a screen-local hex — the refresh spec gives the Coach one
    /// appearance, and a fixed dark ground under ink that resolves per
    /// appearance is what made the session player unreadable in the light one,
    /// so the two travelled together.
    ///
    /// Forcing it dark broke more than it bought. `environment(\.colorScheme:)`
    /// is honoured by SwiftUI and ignored by UIKit, so every navigation bar in
    /// the tab kept resolving the system trait collection and drew a
    /// light-appearance title on this dark ground — which is the contrast
    /// failure the accessibility audit reported against the basics for three
    /// sessions. A tab somebody can sit on is also not a session cover: four
    /// tabs answered the system and the fifth did not.
    func coachGround() -> some View {
        scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RadialGradient(
                    colors: [Theme.Surface.lit, Theme.Surface.ground],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: 900
                )
                .ignoresSafeArea()
            )
    }
}
