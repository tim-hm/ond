import OndKit
import OndUI
import SwiftUI

extension View {
    /// Keeps a board in hand for whichever screen is showing one. Written once
    /// — the Progress card and the full screen both re-ask when the board,
    /// scope or subscription moves, and a second copy of this key is how one
    /// stops refetching after a purchase. What "re-ask" means is `JourneyModel`'s:
    /// a board already loaded or in flight for the same pair is not fetched again.
    func leaderboardFetch(_ model: JourneyModel, unlocked: Bool) -> some View {
        task(id: "\(model.board.rawValue)-\(model.scope.rawValue)-\(unlocked)") {
            await model.loadLeaderboardIfNeeded(unlocked: unlocked)
        }
    }
}

/// One named person on a board: their place, their name, and their figure in
/// the board's own unit.
///
/// One row for the card and the full screen, which had it twice and had already
/// drifted on the rank column's width and the name's weight.
struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let board: LeaderboardBoard

    /// Whether this row is the person reading it. Weight rather than a tint, so
    /// the one row somebody is looking for is marked in a way that survives
    /// both appearances and colour vision.
    var isReader = false

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            Text("\(entry.rank)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.Ink.tertiary)
                .frame(width: 32, alignment: .trailing)

            Text(entry.displayName)
                .font(isReader ? .body.weight(.semibold) : .body)
                .foregroundStyle(Theme.Ink.primary)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.close)

            Text(board.formatted(entry.value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
