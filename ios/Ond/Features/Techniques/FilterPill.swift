import OndUI
import SwiftUI

/// A capsule that narrows a list to one thing, and says whether it is doing so.
///
/// `GoalBadge`'s treatment made into a control: the word in primary ink, the
/// colour carried by the capsule around it. Drawn the obvious way — accent text
/// on a tint of itself — four of the five goal accents miss AA in the light
/// appearance at this size, and `ThemeColorTests` measures the arrangement that
/// replaced it. Selection deepens the fill rather than moving the text into the
/// accent, so the one measured relationship holds in both states: the test's
/// claim is about primary ink over a 0.15 wash, and 0.30 of the same accent is
/// further from the ground in the same direction, never closer.
///
/// The wash sits over an opaque ground capsule rather than directly over the
/// scrolling list. That produces the same measured colour when the row is at
/// rest, while keeping passing titles and summaries out of the pill itself.
///
/// Domain-free even so: it is handed a word and a colour, and that the word is a
/// `TechniqueGoal` and the colour is what that goal is drawn in stays
/// `GoalFilterRow`'s to know. It sits beside that row rather than in `OndUI`
/// because one row in one target draws it, and the escalation rule takes a thing
/// no further than its consumers.
///
/// `.isSelected` rather than a sentence in the label, because a pill is a filter
/// and VoiceOver already has a word for that state — spelling it into the label
/// would have the assistive layer say it twice.
struct FilterPill: View {
    let title: String
    let accent: Color
    let isSelected: Bool
    let select: () -> Void

    /// How much accent the capsule carries unselected, and selected. The first
    /// is `GoalBadge`'s measured wash; the second is as far as it can be
    /// deepened while primary ink still clears AA over every accent in both
    /// appearances.
    private static let fills = (resting: 0.15, selected: 0.3)

    var body: some View {
        Button(action: select) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(Theme.Ink.primary)
                .padding(.horizontal, Theme.Spacing.standard)
                .padding(.vertical, Theme.Spacing.close)
                .background {
                    ZStack {
                        Capsule()
                            .fill(Theme.Surface.ground)

                        Capsule()
                            .fill(accent.opacity(
                                isSelected ? Self.fills.selected : Self.fills.resting
                            ))

                        // Thicker when selected rather than a different colour:
                        // the row is read at a glance and a weight change is
                        // legible without relying on being able to tell two
                        // opacities of one hue apart.
                        Capsule()
                            .stroke(accent, lineWidth: isSelected ? 2 : 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
