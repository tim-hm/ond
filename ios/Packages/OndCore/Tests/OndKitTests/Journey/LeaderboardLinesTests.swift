@testable import OndKit
import Testing

/// The card had one caption for every state that was not a listed board, so a
/// subscriber with a name read the opt-in during every fetch and every outage.
@MainActor
@Suite("The board card's caption")
struct LeaderboardLinesTests {
    private func board(listed: Bool) -> Leaderboard {
        Leaderboard(
            board: .streak,
            scope: .global,
            entries: [],
            standing: LeaderboardStanding(rank: 3, value: 7, listed: listed)
        )
    }

    @Test("says nothing while the board is on its way")
    func quietWhileLoading() {
        #expect(LeaderboardLines.cardCaption(for: .idle) == nil)
        #expect(LeaderboardLines.cardCaption(for: .loading) == nil)
    }

    @Test("names the connection, not the opt-in, when the board is out of reach")
    func unreachableNamesTheConnection() {
        let caption = LeaderboardLines.cardCaption(for: .unreachable)

        #expect(caption?.hasPrefix(LeaderboardLines.unreachable) == true)
        #expect(caption?.contains("put a name") == false)
    }

    @Test("states the wait for a decade the phone has already recorded")
    func decadeIsAwaited() {
        let caption = LeaderboardLines.cardCaption(for: .needsBirthYearBand)

        #expect(caption?.contains("decade") == true)
        #expect(caption?.contains("Pick") == false)
    }

    @Test("says what the board measures once this person is listed")
    func listedReadsTheBoard() {
        let caption = LeaderboardLines.cardCaption(for: .loaded(board(listed: true)))

        #expect(caption == LeaderboardBoard.streak.detail)
    }

    @Test("offers the opt-in only to somebody who has not taken it")
    func unlistedReadsTheOptIn() {
        let caption = LeaderboardLines.cardCaption(for: .loaded(board(listed: false)))

        #expect(caption?.contains("put a name to it") == true)
    }
}
