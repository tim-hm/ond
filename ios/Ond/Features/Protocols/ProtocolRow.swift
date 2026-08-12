import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One protocol: what the moment is called, what it does for you, and what it
/// will cost in minutes.
///
/// Three lines rather than a card, because the list is read top to bottom and a
/// grid of moments would be asking somebody to compare things they are not
/// choosing between — you are in the moment or you are not.
///
/// The wash is the goal's, at the same strength the rest of the app tints a card
/// in. It is the only colour on the row: the name and the facts stay in ink, so
/// a row of six reads as six moments rather than as a palette.
///
/// No Swift type here is called `Protocol`, and none will be — the word is a
/// keyword. The domain kept `Occasion` for the same conversation from the other
/// end: only the interface was renamed.
struct ProtocolRow: View {
    let stop: DialStop
    let tier: SubscriptionTier
    let isStarred: Bool
    let star: () -> Void
    let start: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            Button(action: start) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(stop.title)
                        .font(.headline)
                        .foregroundStyle(Theme.Ink.primary)

                    // Empty where nobody wrote one, and an empty `Text` is a
                    // blank line rather than nothing.
                    if !stop.summary.isEmpty {
                        Text(stop.summary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Ink.secondary)
                    }

                    Text(stop.facts(for: tier))
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The whole row in one utterance, because a label on a button
            // replaces every label composed underneath it — including the
            // "· Plus" and "· on your watch" marks a sighted reader gets from
            // the caption.
            .accessibilityLabel(stop.spokenLabel(for: tier))
            .accessibilityHint("Starts the session")

            StopStarButton(stop: stop, isStarred: isStarred, star: star)
        }
        .padding(.leading, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(
            stop.goal.accent.opacity(0.12),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
    }
}
