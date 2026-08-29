import OndKit
import OndUI
import SwiftUI

/// The one drawing of the star on a stop; two screens once carried
/// byte-for-byte copies. It cannot move to `OndUI`, which must not learn
/// `DialStop`, and it is not `TechniqueStarButton`, which stars an exercise.
/// It is told `isStarred` rather than reading the store: a second reader
/// would invalidate a list nobody is looking at on every distant star tap.
struct StopStarButton: View {
    let stop: DialStop
    let isStarred: Bool
    let star: () -> Void

    var body: some View {
        Button(action: star) {
            // Colour rather than fill, which the toolbar's star cannot afford
            // and this can: nothing here already wears the tint, so the brand
            // tone is free to carry the state.
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isStarred ? Theme.Accent.brand : Theme.Ink.tertiary)
                // The glyph is small and the corner it sits in is smaller. The
                // width is what stops this being a control only a precise thumb
                // can reach.
                .frame(width: Theme.Metrics.minimumTapTarget)
                .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarred ? "Unstar \(stop.title)" : "Star \(stop.title)")
    }
}
