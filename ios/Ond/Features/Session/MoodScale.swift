import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The five-point pleasantness scale, drawn once before the breathing and once
/// after — see `MoodCheckView` and `SessionSummaryView`.
///
/// Anchored rather than labelled: the ends carry the words and the points
/// between them carry position, which is how every scale of this kind is read
/// and the only way five of them fit a phone's width without abbreviating the
/// words into something nobody would recognise. VoiceOver gets the full word on
/// every point, so nothing is inferred from position there.
///
/// Equal circles, deliberately. Grading their size or their colour would draw
/// one end as better than the other, and this is a scale somebody reports
/// themselves on twice — not a target to move toward.
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

    private static let diameter: CGFloat = 26

    var body: some View {
        VStack(spacing: Theme.Spacing.close) {
            HStack(spacing: 0) {
                ForEach(Mood.allCases) { mood in
                    point(mood)
                }
            }

            HStack {
                Text(Mood.veryUnpleasant.title)
                Spacer()
                Text(Mood.veryPleasant.title)
            }
            .font(.caption)
            .accessibilityHidden(true)
        }
    }

    private func point(_ mood: Mood) -> some View {
        Button {
            onSelect(mood)
        } label: {
            Circle()
                .fill(mood == selection ? Theme.Ink.primary : Color.clear)
                .overlay(Circle().strokeBorder(Theme.Ink.primary, lineWidth: 1.5))
                .frame(width: Self.diameter, height: Self.diameter)
                // The whole slot, not the circle: five 26pt discs would each
                // be under the minimum, and the gap between them is dead space
                // that has nowhere else to go.
                .tapTarget(spanningWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(mood == selection ? [.isSelected] : [])
    }
}
