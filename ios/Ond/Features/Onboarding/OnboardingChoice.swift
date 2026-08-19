import OndUI
import SwiftUI

/// One goal someone can pick, as a word-sized chip in the wrapping goal field.
///
/// The coloured dot introduces goals as the app's register colours. Selection
/// uses tint, border and text together rather than adding a checkmark, keeping
/// the five compact enough to read as one field.
struct OnboardingChoice: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let selectedText: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.close) {
                Circle()
                    .fill(accent.opacity(isSelected ? 1 : 0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? selectedText : Theme.Ink.secondary)
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .frame(height: 42)
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? accent.opacity(Theme.Fill.selection)
                            : Theme.Ink.primary.opacity(0.045)
                    )
                    .stroke(
                        isSelected ? accent.opacity(0.5) : Theme.Surface.line,
                        lineWidth: 1
                    )
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
