import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The goal a technique serves, as a capsule — the way the suggestion strip and
/// a protocol card say what the catalogue row says in its caption's first word.
///
/// The word is set in ink and the goal's colour is carried by the capsule around
/// it. Drawn the obvious way — accent text on a 0.15 tint of itself — four of
/// the five accents miss AA in the light appearance at the `.caption2` this is
/// set in. `ThemeColorTests` measures the treatment that replaced it.
///
/// At `ios/Ond/` rather than inside a feature because two features draw it and
/// neither owns it: the escalation rule in docs/code-structure.md, taken one
/// step and no further. It cannot go on to `OndUI`, which knows nothing about a
/// `TechniqueGoal`.
struct GoalBadge: View {
    let goal: TechniqueGoal

    var body: some View {
        Text(goal.title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Ink.primary)
            .padding(.horizontal, Theme.Spacing.close)
            .padding(.vertical, Theme.Spacing.tight)
            .background {
                Capsule()
                    .fill(goal.accent.opacity(0.15))
                    .stroke(goal.accent, lineWidth: 1)
            }
    }
}
