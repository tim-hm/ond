import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The five ways somebody can answer how they feel, drawn on the countdown
/// before the breathing and on the summary after — see `CountdownView` and
/// `SessionSummaryView`. Numerals with the two ends named: five words do not
/// fit across a phone. Every choice keeps equal visual weight — this is a
/// report, not a target to move toward. It draws in whatever ink it inherits.
struct MoodScale: View {
    /// The point already chosen, filled in rather than outlined. Nil until the
    /// first tap, and the scale never returns to nil — a mood is answered once.
    /// Defaulted for the summary's row, which swaps the scale for a sentence
    /// the moment it has an answer and so never draws a selected point.
    var selection: Mood?

    let onSelect: (Mood) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tighter than `Theme.Radius.card` on purpose: this is a control inside a
    /// screen, not a card on one, and a card's corner at this size reads as a
    /// pill. The selection's corner below is derived, not chosen — concentric
    /// corners are the outer radius less the inset between the two shapes.
    private static let cornerRadius: CGFloat = 14
    private static let selectionInset: CGFloat = 3

    var body: some View {
        VStack(spacing: Theme.Spacing.tight) {
            points

            // The stacked layout says every word already, so a pair of ends
            // under it would name two of the five points twice.
            if !isStacked {
                ends
            }
        }
    }

    /// Whether the points are drawn down the screen rather than across it. At
    /// an accessibility size five numerals in a row leave no width to read
    /// them in, and the height a stack costs is height that size asked for.
    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var points: some View {
        layout {
            ForEach(Mood.allCases) { mood in
                choice(mood)
            }
        }
        .padding(Self.selectionInset)
        .background(
            Theme.Surface.raised.opacity(0.6),
            in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        )
    }

    /// What the numerals mean, at the only two points that need saying. Hidden
    /// from VoiceOver, which hears each point's own word instead.
    private var ends: some View {
        HStack(spacing: Theme.Spacing.close) {
            Text(Mood.lowest.title)
            Spacer(minLength: 0)
            Text(Mood.highest.title)
        }
        .font(.footnote)
        .accessibilityHidden(true)
    }

    private var layout: AnyLayout {
        if isStacked {
            AnyLayout(VStackLayout(spacing: 0))
        } else {
            AnyLayout(HStackLayout(spacing: 0))
        }
    }

    private func choice(_ mood: Mood) -> some View {
        let isSelected = mood == selection

        return Button {
            onSelect(mood)
        } label: {
            Text(isStacked ? mood.title : "\(mood.position)")
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.close)
                .tapTarget()
                .background {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: Self.cornerRadius - Self.selectionInset,
                            style: .continuous
                        )
                        .fill(Theme.Ink.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
