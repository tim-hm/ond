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

    /// The colour the caller has already resolved, where it has one the goal
    /// cannot answer with. A Moment card passes `DialStop.accent`, which a
    /// playful route colours itself; a suggestion holds only an exercise.
    var accent: Color?

    private var tint: Color {
        accent ?? goal.accent
    }

    var body: some View {
        Text(goal.title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Ink.primary)
            .padding(.horizontal, Theme.Spacing.close)
            .padding(.vertical, Theme.Spacing.tight)
            .background {
                Capsule()
                    .fill(tint.opacity(0.15))
                    .stroke(tint, lineWidth: 1)
            }
    }
}
