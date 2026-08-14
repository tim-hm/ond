import OndUI
import SwiftUI

/// A compact filter that narrows a list to one goal, and says whether it is
/// doing so.
///
/// The resting surface is neutral so five filters do not become five competing
/// outlined fields. A dot keeps the goal's identity visible; selection washes
/// the whole surface in that colour. The word remains in primary ink because
/// four of the five goal accents miss AA as small text in the light appearance,
/// while `ThemeColorTests` measures primary ink over the selected wash.
///
/// Its visible capsule is deliberately shorter than its hit area. The quiet
/// visual weight belongs beside a title; the 44-point target belongs under a
/// finger, and `tapTarget()` provides it without making the fill look bulky.
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

    /// As far as the selected surface can be deepened while primary ink still
    /// clears AA over every accent in both appearances.
    private static let selectedFill = 0.3

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.Ink.primary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background {
                ZStack {
                    Capsule().fill(Theme.Surface.raised)

                    if isSelected {
                        Capsule().fill(accent.opacity(Self.selectedFill))
                    }
                }
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
