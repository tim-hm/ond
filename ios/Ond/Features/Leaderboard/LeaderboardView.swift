import OndKit
import OndUI
import SwiftUI

/// The one part of the journey that genuinely needs a connection — said
/// quietly, never as an error: a person with no signal has lost nothing they
/// own. Only people who chose a display name are listed, but everybody with a
/// score counts in the ranking — which is why entries can skip a number.
struct LeaderboardView: View {
    let model: JourneyModel
    let profiles: ProfileStore

    @Environment(SubscriptionStore.self) private var plus

    var body: some View {
        ScrollView {
            if isUnlocked {
                unlocked
            } else {
                locked
            }
        }
        .paletteGround()
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
        // Not fetched below the subscription: the server refuses the call with
        // PERMISSION_DENIED, and asking anyway would draw the unreachable state
        // over an offer — telling somebody their signal is bad when it is their
        // subscription. The model holds that rule, and with it the one that
        // stops this screen refetching what the card that opened it already has.
        .leaderboardFetch(model, unlocked: isUnlocked)
    }

    private var isUnlocked: Bool {
        plus.tier >= .leaderboards
    }

    /// The offer, in the shape the Coach tab's closed room uses. A board is a
    /// fold across everybody who practises — this phone cannot compute it and
    /// the server will not for free, so this is the one screen whose *whole
    /// content* sits behind the subscription.
    private var locked: some View {
        ContentUnavailableView {
            Label("See where you stand", systemImage: "trophy")
        } description: {
            Text(
                "Streaks, minutes and comfortable pauses, ranked against everybody "
                    + "practising — and against people born in the same decade as you."
            )
        } actions: {
            UpgradePrompt(reason: "The boards are part of", for: .leaderboards)
        }
        .padding(Theme.Spacing.standard)
    }

    private var unlocked: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            Picker("Board", selection: $model.board) {
                ForEach(LeaderboardBoard.allCases) { board in
                    Text(board.title).tag(board)
                }
            }
            .pickerStyle(.segmented)

            Text(model.board.detail)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)

            // Offered only when there is a decade to compare within: a scope
            // the server would refuse is not a choice worth showing.
            if profiles.profile.birthYearBand != nil {
                Picker("Scope", selection: $model.scope) {
                    ForEach(LeaderboardScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            board
            optIn
        }
        .padding(Theme.Spacing.standard)
    }

    @ViewBuilder
    private var board: some View {
        switch model.leaderboard {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.loose)

        case .unreachable:
            VStack(spacing: Theme.Spacing.close) {
                Text("Leaderboards need a connection")
                    .font(.headline)
                Text("Everything else here is on your phone and stays there.")
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.loose)

        case .needsBirthYearBand:
            // Reachable because the picker offers this scope from the local
            // profile, which carries the decade the moment it is picked — before
            // the server has it. Saying "no connection" here would be a lie to
            // somebody with full signal, and the answer is one screen away.
            DoorCard(
                title: "Pick your decade",
                caption: "This board compares you with people born around the same time. "
                    + "Choose a decade and it fills in."
            ) {
                LeaderboardNameView(profiles: profiles)
            }
            .glassCard(interactive: true)

        case let .loaded(leaderboard):
            standing(leaderboard)
            entries(leaderboard)
        }
    }

    private func standing(_ leaderboard: Leaderboard) -> some View {
        let standing = leaderboard.standing

        return VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(standing.formattedRank.map { "You're \($0)" } ?? "Nothing to rank yet")
                .font(.headline)

            Text(
                standing.rank == nil
                    ? "A session or two and you'll be on here."
                    : "\(leaderboard.board.formatted(standing.value))"
                    + (standing.listed ? "" : " · only you can see this")
            )
            .font(.caption)
            .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        // Neutral glass rather than a brand wash: at 0.12 the tint sat within
        // a few points of the plain raised card in the dark appearance, so it
        // coloured nothing legibly.
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entries(_ leaderboard: Leaderboard) -> some View {
        if leaderboard.entries.isEmpty {
            Text("Nobody has put a name to this board yet.")
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(leaderboard.entries) { entry in
                    LeaderboardRow(
                        entry: entry,
                        board: leaderboard.board,
                        isReader: entry.displayName == profiles.profile.displayName
                    )
                    .padding(.vertical, Theme.Spacing.close)

                    Divider().overlay(Theme.Surface.line)
                }
            }
        }
    }

    private var optIn: some View {
        DoorCard(
            title: profiles.profile.displayName.isEmpty ? "Join in" : "Your name",
            caption: profiles.profile.displayName.isEmpty
                ? "Pick a name and others can see you here. Leave it blank and nobody can."
                : profiles.profile.displayName
        ) {
            LeaderboardNameView(profiles: profiles)
        }
        .glassCard(interactive: true)
    }
}
