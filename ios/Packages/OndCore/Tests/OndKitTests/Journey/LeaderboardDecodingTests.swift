import Foundation
import OndAPI
@testable import OndKit
import Testing

/// The outbound half of the leaderboard contract, which nothing else holds.
/// The server pins the inbound half, and that leaves this side unguarded:
/// both enums match their proto counterparts in arity, so a swapped arm
/// type-checks, the server answers happily, and the answer is labelled with
/// the board that was *asked for* — the wrong board under the right heading.
@Suite("Mapping leaderboard choices onto the wire")
struct LeaderboardDecodingTests {
    @Test("Each board maps to the proto case that names it, and no other")
    func boardsMapOneForOne() {
        #expect(LeaderboardBoard.streak.proto == .streak)
        #expect(LeaderboardBoard.minutes30d.proto == .minutes30D)
        #expect(LeaderboardBoard.bolt.proto == .bolt)
    }

    @Test("Each scope maps to the proto case that names it, and no other")
    func scopesMapOneForOne() {
        #expect(LeaderboardScope.global.proto == .global)
        #expect(LeaderboardScope.ageBand.proto == .ageBand)
    }

    /// The proto's zero value is the server's refusal, so an arm reaching it
    /// turns a board somebody picked into an `INVALID_ARGUMENT` — and this app
    /// reads that as "leaderboards need a connection". Written over `allCases`
    /// so a board added later is covered before anyone thinks to add a line.
    @Test("Nothing a person can pick maps onto the proto zero value")
    func nothingMapsOntoUnspecified() {
        for board in LeaderboardBoard.allCases {
            #expect(board.proto != .unspecified)
        }
        for scope in LeaderboardScope.allCases {
            #expect(scope.proto != .unspecified)
        }
    }
}
