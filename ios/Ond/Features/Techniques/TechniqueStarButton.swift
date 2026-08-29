import OndKit
import SwiftUI

/// Keep this one near the top — "that one, whatever the goal says". Its own
/// type: reading `starred` inside the detail screen's body would redraw its
/// figures for a star tapped two tabs away. It fills and clears against every
/// card standing for this exercise, `DialStop.ids(standingFor:)`; starring
/// writes only `DialStop.id(of:)`, the join `HomeOffer` matches against.
struct TechniqueStarButton: View {
    let technique: Technique

    @Environment(StarredStopStore.self) private var stars

    var body: some View {
        let isStarred = DialStop.isStarred(technique, among: stars.starred)

        // Fill rather than colour, which the board's star can afford and this
        // cannot: a toolbar item already wears the app's tint, so a brand-coloured
        // glyph would be a control with no visible state. The bar owns the hit
        // target and the metrics too — the 44pt frame the board's star sets by hand
        // would draw a shape this bar did not size.
        return Button {
            if isStarred {
                stars.unstar(DialStop.ids(standingFor: technique))
            } else {
                stars.star(DialStop.id(of: technique))
            }
        } label: {
            Label("Star", systemImage: isStarred ? "star.fill" : "star")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(isStarred ? "Unstar \(technique.name)" : "Star \(technique.name)")
    }
}
