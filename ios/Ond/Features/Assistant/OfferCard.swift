import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The shell every card under a coach reply wears: an eyebrow naming what the
/// offer is for, the offer itself, and the action that takes it.
///
/// Three cards had written this out separately — an exercise to start, a
/// pattern to save, a pause to take — and the three had already drifted on
/// whether the summary line existed at all. What differs between them is the
/// action, which is what they still each own.
///
/// **The goal carries the card.** The chat itself is neutral: a transcript
/// tinted per turn would be a conversation in five colours, and the person did
/// not choose a goal by asking a question. An offer is different — it is the
/// coach naming an exercise, and what that exercise is for is the first thing
/// worth knowing about it.
///
/// The eyebrow takes `textAccent` rather than the fill's own accent: over its
/// own 22% wash a goal reads between 4.54:1 and 4.91:1, and sleep only gets
/// there through the lifted `Accent.nightText`, which is the case that pair was
/// built for. The 40% hairline is reinforcement — at about 2.2:1 it is an edge
/// rather than a carrier, and the eyebrow and the fill both say the same thing.
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

    /// The height every action on an offer card stands at. A minimum rather
    /// than a fixed height, so a button whose label wraps at a larger text
    /// size grows instead of clipping.
    ///
    /// Computed rather than stored because this type is generic over its
    /// actions, and a generic type cannot hold a static stored property.
    private static var actionHeight: CGFloat {
        42
    }
}
