import OndUI
import SwiftUI

/// A compact filter that narrows a list to one goal. Selection washes the
/// surface in the goal's accent; the word stays primary ink — light accents
/// measure 3.64–4.27:1 over their own wash, under 4.5:1 (`ThemeColorTests`).
/// The capsule is deliberately shorter than its `tapTarget()` hit area.
/// `.isSelected`, not a label sentence: VoiceOver would say the state twice.
struct FilterPill: View {
    let title: String
    let accent: Color
    let isSelected: Bool
    var showsDot = true
    let select: () -> Void

    /// The spec's selected pill: an 18% fill under a 55% ring. The ring
    /// reinforces rather than carries — at 55% it measures about 2.2:1, under
    /// the 3:1 a sole carrier would owe — but the fill, the word's weight and
    /// the `.isSelected` trait each say the same thing. `ThemeColorTests`
    /// measures the fill.
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
