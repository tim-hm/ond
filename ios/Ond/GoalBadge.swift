import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The goal a technique serves, as a capsule. The word is set in ink and the
/// goal's colour carried by the capsule: accent text on a 0.15 tint of itself
/// misses AA for four of the five accents at `.caption2` in light —
/// `ThemeColorTests` measures the treatment. At `ios/Ond/` because two
/// features draw it; `OndUI` knows nothing about a `TechniqueGoal`.
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
