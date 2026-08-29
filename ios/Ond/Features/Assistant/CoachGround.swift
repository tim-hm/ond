import OndUI
import SwiftUI

extension View {
    /// The Coach tab's own ground: a radial lifting towards the top-left
    /// corner, falling to the palette's base surface. Both ends are tokens, so
    /// the tab follows the system appearance. It used to force itself dark,
    /// but UIKit ignores `environment(\.colorScheme:)`, so every navigation bar
    /// drew a light-appearance title on it — an audited contrast failure.
    func coachGround() -> some View {
        scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RadialGradient.groundGlow(from: UnitPoint(x: 0.2, y: 0), reach: 900)
                    .ignoresSafeArea()
            )
    }
}
