import Foundation
import OndAPI
@testable import OndKit
import Testing

@Suite("What one page of a reinstall restore asks the server for")
struct JourneyRestoreRequestTests {
    /// The restore reads only sessions and the page token, so it says so —
    /// `sessions_only` in `journey_service.proto` — saving three of the four
    /// heaviest per-person queries on up to forty consecutive pages. Asserted on
    /// the *first* page above all: keying on the presence of a page token would
    /// exempt exactly the one page every restore makes.
    @Test func everyRestorePageAsksForSessionsAlone() {
        let first = JourneyRepository.restorePage(after: nil)
        #expect(first.sessionsOnly)
        #expect(!first.hasPageToken, "the first page carries no token")

        let next = JourneyRepository.restorePage(after: "opaque-server-token")
        #expect(next.sessionsOnly, "and so does every page behind it")
        #expect(next.pageToken == "opaque-server-token")
    }

    /// The page size is the server's own ceiling, so a long history costs the
    /// fewest round trips it can — and the offset still rides along, because the
    /// request is shared with the screen that computes local-day streaks.
    @Test func aRestorePageAsksForTheServersCeiling() {
        let request = JourneyRepository.restorePage(after: nil)

        #expect(request.limit == 500)
        #expect(request.utcOffsetMinutes == Int32(TimeZone.current.secondsFromGMT() / 60))
    }
}
