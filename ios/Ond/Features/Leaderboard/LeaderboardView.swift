import OndKit
import OndUI
import SwiftUI

/// The one part of the journey that genuinely needs a connection.
///
/// So it says so, quietly, and never as an error: everything else on the tab is
/// already on screen, and a person with no signal has lost nothing they own.
///
/// Only people who have chosen a display name are listed. Everybody with a score
/// is counted in the ranking, which is why the entries can skip a number — the
/// person in between is here and invisible.
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
        // subscription.
        .task(id: reloadKey) {
            guard isUnlocked else { return }
            await model.loadLeaderboard()
        }
    }

    private var isUnlocked: Bool {
        plus.tier >= .leaderboards
    }

    /// The offer, in the shape the Coach tab's closed room uses.
    ///
    /// A board is a fold across everybody who practises, which this phone cannot
    /// compute and the server will not compute for free — so this is the one
    /// screen in the app whose *whole content* is behind the subscription rather
    /// than a feature layered onto something free.
    private var locked: some View {
        ContentUnavailableView {
            Label("See where you stand", systemImage: "trophy")
        } description: {
            Text(
                "Streaks, minutes and breath-holds, ranked against everybody "
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

    /// Changing either dimension is a different board, so the fetch is keyed on
    /// both rather than driven from two `onChange` handlers that could race.
    ///
    /// The subscription is part of the key for a third reason: buying önd+ from
    /// the locked screen above changes what this view may fetch, and a key that
    /// did not move would leave the task already run — an offer replaced by a
    /// spinner that never resolves, on the screen somebody just paid to see.
    private var reloadKey: String {
        "\(model.board.rawValue)-\(model.scope.rawValue)-\(isUnlocked)"
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
                    HStack {
                        Text("\(entry.rank)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.Ink.tertiary)
                            .frame(width: 32, alignment: .trailing)

                        Text(entry.displayName)
                            .font(.body)

                        Spacer()

                        Text(leaderboard.board.formatted(entry.value))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.close)
                    .accessibilityElement(children: .combine)

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
    }
}
