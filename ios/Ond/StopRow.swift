import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One thing you can breathe, as a row: what it is called, optionally what it
/// does for you, and what it will cost in minutes.
///
/// One type for Home's three sections and the Protocols list, which had two
/// copies of this shell between them — already disagreeing about the ink under
/// the name, with nothing anywhere saying why. The star was deduplicated a
/// commit earlier for the same reason and by the same argument: a row is a
/// handful of decisions about weight, wash and target, and no screen should be
/// able to make them differently from the one beside it.
///
/// The wash is the goal's, at the strength the rest of the app tints a card in.
/// It is the only colour on the row: the name and the facts stay in ink, so a
/// column of six reads as six offers rather than as a palette.
///
/// Rows are told whether they are starred rather than reading the store, on
/// `StopStarButton`'s reasoning — but the *rule* for what starred means is
/// `StarredStopStore.isStarred(_:)`, because "is this exercise pinned" has an
/// answer no single id can give.
struct StopRow: View {
    let stop: DialStop
    let tier: SubscriptionTier

    /// The sentence between the name and the facts, where there is room for one.
    ///
    /// The Protocols list shows it — a moment's own words are most of why
    /// somebody picks it — and Home does not, because its sections are already
    /// captioned and a paragraph per starred row would make the shelf the
    /// longest thing on the screen.
    var showsSummary = false

    @Environment(StarredStopStore.self) private var stars

    let start: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            Button(action: start) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(stop.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Ink.primary)

                    // Empty where nobody wrote one, and an empty `Text` is a
                    // blank line rather than nothing.
                    if showsSummary, !stop.summary.isEmpty {
                        Text(stop.summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.Ink.secondary)
                    }

                    Text(stop.facts(for: tier))
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Spoken whole, because a label on a button replaces every label
            // composed under it — including the "· Plus" and "· on your watch"
            // marks the caption carries for a sighted reader.
            .accessibilityLabel(stop.spokenLabel(for: tier))
            .accessibilityHint("Starts the session")

            StopStarButton(stop: stop, isStarred: stars.isStarred(stop)) {
                stars.toggle(stop)
            }
        }
        .padding(.leading, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(
            stop.goal.accent.opacity(0.12),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
    }
}
