import OndKit
import OndUI
import SwiftUI

/// Where this person stands, inline on the Progress screen, and the way to
/// the full board. It draws whichever board `JourneyModel.board` holds, which is
/// the person's own selection. A card that picked its own board would overwrite
/// that selection, or fetch a second board to disagree with it.
struct BoardCard: View {
    let model: JourneyModel
    let profiles: ProfileStore

    @Environment(SubscriptionStore.self) private var plus

    /// How many named people the card lists before the full screen is the
    /// better place to keep reading.
    private static let shown = 3

    var body: some View {
        NavigationLink {
            LeaderboardView(model: model, profiles: profiles)
        } label: {
            card
        }
        // Plain, because the default link style tints the whole card in the
        // accent, and the chevron already says it is a way in.
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboards-door")
        .leaderboardFetch(model, unlocked: isUnlocked)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(spacing: Theme.Spacing.close) {
                // The width is claimed rather than left to a `Spacer`: an
                // `HStack` hands a text its *ideal* width, so at the larger
                // type sizes "You're 12th on resting rate" would be squeezed
                // beside the chevron and truncated instead of wrapping under
                // it.
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Ink.tertiary)
                    .accessibilityHidden(true)
            }

            entries

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .padding(Theme.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(interactive: true)
    }

    /// The top of the board, where there is a loaded one to draw. No spinner
    /// and no failure notice otherwise: rows are the one part of this card
    /// that needs the network, and a card on a screen full of local numbers
    /// must not make the whole tab look as though it were waiting. The caption
    /// carries whatever the state is worth saying.
    @ViewBuilder
    private var entries: some View {
        if case let .loaded(leaderboard) = model.leaderboard, !leaderboard.entries.isEmpty {
            VStack(spacing: Theme.Spacing.tight) {
                ForEach(leaderboard.entries.prefix(Self.shown)) { entry in
                    LeaderboardRow(
                        entry: entry,
                        board: leaderboard.board,
                        isReader: entry.displayName == profiles.profile.displayName
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.tight)
        }
    }

    private var isUnlocked: Bool {
        plus.tier >= .leaderboards
    }

    /// The card's first line: this person's place where the board can say one,
    /// and the feature's name where it cannot.
    private var headline: String {
        guard isUnlocked, case let .loaded(leaderboard) = model.leaderboard,
              let rank = leaderboard.standing.formattedRank
        else { return "Leaderboards" }

        return "You're \(rank) on \(model.board.title.lowercased())"
    }

    /// What sits under the rows: the offer below the tier, and whatever the
    /// board itself can honestly say above it.
    private var caption: String? {
        isUnlocked ? LeaderboardLines.cardCaption(for: model.leaderboard) : Self.offer
    }

    /// Named here rather than in `LeaderboardLines`, because the tier's name
    /// is an app-local extension that package cannot see.
    private static let offer =
        "Streaks, comfortable pauses, resting breathing and minutes, ranked against "
            + "everybody practising. Part of \(SubscriptionTier.leaderboards.title)."
}
