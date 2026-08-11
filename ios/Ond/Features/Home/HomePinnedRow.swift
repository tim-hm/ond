import OndKit
import OndUI
import SwiftUI

/// One singled-out exercise, at row height rather than as a square card.
///
/// The same vocabulary as a tile — the goal wash, the silhouette, the star — in a
/// different proportion, and the proportion is the whole point. A card says "here
/// are six things, compare them"; a row says "this one, and here it is". Two shapes
/// on one screen is what lets the strip read as a shortlist rather than as the first
/// two cards of the board.
///
/// It carries exactly what a tile carries, in one line instead of a block: a row that
/// dropped the length or the reason would make the strip a place where you learn less
/// about the exercises you care most about.
struct HomePinnedRow: View {
    let card: HomeDeck.Card
    let tier: SubscriptionTier
    let isStarred: Bool
    let star: () -> Void
    let start: () -> Void

    var body: some View {
        let stop = card.stop

        return HStack(spacing: Theme.Spacing.standard) {
            Button(action: start) {
                HStack(spacing: Theme.Spacing.standard) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stop.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Ink.primary)
                            .lineLimit(1)

                        Text(facts(stop))
                            .font(.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.title), \(card.reason.phrase)")
            .accessibilityHint("Starts the session")

            if card.reason.acceptsStar {
                starButton(stop)
            } else {
                // The suggestion's row keeps the width the star would have taken, so
                // the strip's names line up rather than one running further right than
                // the rest.
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.leading, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(
            stop.goal.accent.opacity(0.12),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
    }

    /// The reason and the two facts, on the one line a row has for them.
    ///
    /// `brief` rather than `phrase`: the sentence a card can finish would push the
    /// length off the end of the line, and the length is the fact somebody choosing
    /// between a shortlist of four actually needs.
    ///
    /// A starred row drops the reason entirely — the filled star two inches to the
    /// right is already saying it. See `HomeDeck.Reason.isSpelled`.
    private func facts(_ stop: DialStop) -> String {
        let length = stop.duration.formatted(
            .units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
        let locked = stop.technique.isUnlocked(for: tier) ? "" : " · Plus"
        let wrist = stop.surface == .discreet ? " · on your watch" : ""
        let said = card.reason.isSpelled ? "\(card.reason.brief) · " : ""

        return "\(said)\(stop.goal.intentObject) · \(length)\(locked)\(wrist)"
    }

    private func starButton(_ stop: DialStop) -> some View {
        Button(action: star) {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isStarred ? Theme.Accent.brand : Theme.Ink.tertiary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarred ? "Unstar \(stop.title)" : "Star \(stop.title)")
    }
}
