import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The three ways somebody can answer how they feel, drawn once before the
/// breathing and once after — see `MoodCheckView` and `SessionSummaryView`.
///
/// Directly labelled rather than inferred from position: three short answers fit
/// without abbreviation, and asking somebody to act during a countdown leaves
/// no room for decoding an unlabelled scale. Every choice has equal visual
/// weight because this is a report, not a target to move toward.
///
/// Drawn in whatever ink it inherits, which on both its screens is the primary
/// tone `accentGround(_:)` calls for.
struct MoodScale: View {
    /// The point already chosen, filled in rather than outlined. Nil until the
    /// first tap, and the scale never returns to nil — a mood is answered once.
    /// Defaulted for the summary's row, which swaps the scale for a sentence
    /// the moment it has an answer and so never draws a selected point.
    var selection: Mood?

    let onSelect: (Mood) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout {
            ForEach(Mood.allCases) { mood in
                choice(mood)
            }
        }
    }

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(spacing: Theme.Spacing.close))
        } else {
            AnyLayout(HStackLayout(spacing: Theme.Spacing.close))
        }
    }

    private func choice(_ mood: Mood) -> some View {
        let isSelected = mood == selection

        return Button {
            onSelect(mood)
        } label: {
            Text(mood.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.close)
                .padding(.vertical, Theme.Spacing.close)
                .background {
                    ZStack {
                        Capsule().fill(Theme.Surface.raised.opacity(0.6))
                        if isSelected {
                            Capsule().fill(Theme.Ink.primary.opacity(0.12))
                        }
                    }
                }
                .overlay(
                    Capsule().strokeBorder(
                        Theme.Ink.primary,
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
