import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The shell every card under a coach reply wears; three cards had each
/// written it out and drifted. The goal carries the card's one colour — the
/// chat itself stays neutral. The eyebrow takes `textAccent`, not the fill's
/// accent: over the 22% wash a goal reads 4.54:1–4.91:1, sleep only through
/// the lifted `Accent.nightText`. The 40% hairline (~2.2:1) is an edge, not a carrier.
struct OfferCard<Actions: View>: View {
    /// What kind of offer this is, in the card's own two or three words.
    let eyebrow: String
    let title: String

    /// The line under the title.
    let summary: String

    /// What the offer is for, which is the card's one colour.
    let goal: TechniqueGoal

    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(eyebrow)
                .eyebrow(goal.textAccent)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(Theme.Ink.secondary)

            // The height is applied here rather than left to each card, so a
            // fourth offer cannot stand two points short of the three beside
            // it — the drift this shell was extracted to end.
            actions()
                .frame(minHeight: Self.actionHeight)
                .padding(.top, Theme.Spacing.tight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .background(
            LinearGradient(
                colors: [goal.accent.opacity(0.22), goal.accent.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(goal.accent.opacity(0.40), lineWidth: 0.5)
        )
    }

    /// The height every action on an offer card stands at — a minimum, so a
    /// label that wraps at a larger text size grows instead of clipping.
    /// Computed because a generic type cannot hold a static stored property.
    private static var actionHeight: CGFloat {
        42
    }
}
