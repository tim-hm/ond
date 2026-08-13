import OndKit
import OndUI
import SwiftUI

/// Keep this one in front of you.
///
/// One type for every row that offers a star — Home's shelf and the Protocols
/// list — which had the same control twice, byte for byte, differing only in
/// where each got its answer from. A star is small enough that two copies
/// drifting is easy to miss and easy to do: the glyph, the weight, the two tones
/// and the target are four decisions, and no screen should be able to make them
/// differently from the one beside it.
///
/// At `ios/Ond/` rather than inside a feature because two features draw it and
/// neither owns it — the escalation rule in docs/code-structure.md, taken one
/// step and no further. It cannot go on to `OndUI`, which knows nothing about a
/// `DialStop` and must not learn.
///
/// Not `TechniqueStarButton`, which looks like the same control and is not. That
/// one stars an *exercise* from the detail screen's toolbar, against every stop
/// standing for it, and states at length why it sets no frame of its own — the
/// bar owns its metrics. This stars one *stop*, in a corner it has to earn a
/// target in.
///
/// It is told whether it is starred rather than reading the store. Both callers
/// already hold the starred set for their own layout, and `TechniqueStarButton`
/// records what a second reader would cost: a star tapped two tabs away would
/// invalidate a list nobody is looking at.
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
