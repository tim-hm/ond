import Foundation

/// What the leaderboard says about itself, on the Progress card and on the
/// board screen. Here rather than in either view because the app target has
/// no tests of its own, and this is the rule a screen gets silently wrong:
/// any state left unnamed reads as the opt-in, which tells somebody who has
/// already chosen a name that they have none.
public enum LeaderboardLines {
    /// The card's caption, or nothing while the board is on its way. The
    /// offer below the subscription is not here: it names the tier through an
    /// app-local extension this package cannot see.
    @MainActor
    public static func cardCaption(for state: JourneyModel.LeaderboardState) -> String? {
        switch state {
        case .idle, .loading:
            nil

        case .unreachable:
            "\(unreachable). \(unreachableDetail)"

        // Reached only by somebody whose decade is already set locally, so the
        // card states the wait rather than asking again for what it has.
        case .needsBirthYearBand:
            "Your decade hasn't reached the board yet."

        case let .loaded(leaderboard):
            leaderboard.standing.listed ? leaderboard.board.detail : unlisted
        }
    }

    /// The board screen heads its notice with this and puts the detail under
    /// it; the card says both as one sentence. One spelling, because two of
    /// them drift apart and only one of them is under test.
    public static let unreachable = "Leaderboards need a connection"
    public static let unreachableDetail = "Everything else here is on your phone and stays there."

    /// The opt-in, in the words the whole feature is bound by.
    private static let unlisted =
        "Off until you put a name to it. "
            + "It ranks streaks, comfortable pauses, resting breathing and minutes."
}
