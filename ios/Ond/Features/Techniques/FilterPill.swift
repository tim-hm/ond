import OndUI
import SwiftUI

/// A compact filter that narrows a list to one goal, and says whether it is
/// doing so.
///
/// The resting surface is neutral so five filters do not become five competing
/// outlined fields. A dot keeps the goal's identity visible; selection washes
/// the whole surface in that colour and rings it in the same accent at
/// stroke strength, which is the refresh spec's treatment. The word remains in
/// primary ink where the spec sets it in the accent: over an 18% wash of its
/// own colour, the light appearance's goal accents measure 3.64:1 to 4.27:1
/// against a 4.5:1 floor, so the accent carries the fill and the ring while ink
/// carries the word. `ThemeColorTests` measures that pairing.
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
    var showsDot = true
    let select: () -> Void

    /// The spec's selected pill: an 18% fill under a 55% ring. Shallower than
    /// the 0.30 wash it replaces, which had to carry selection alone.
    ///
    /// The ring reinforces rather than carries: at 55% over the light ground it
    /// measures around 2.2:1, under the 3:1 a sole carrier would owe. It does
    /// not have to be one — the fill, the word's weight and the `.isSelected`
    /// trait each say the same thing — which is why the fill is what
    /// `ThemeColorTests` measures.
    private static let selectedFill = Theme.Fill.selection
    private static let selectedBorder = 0.55

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                if showsDot {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }

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
                        Capsule()
                            .fill(accent.opacity(Self.selectedFill))
                            .stroke(accent.opacity(Self.selectedBorder), lineWidth: 1)
                    }
                }
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
