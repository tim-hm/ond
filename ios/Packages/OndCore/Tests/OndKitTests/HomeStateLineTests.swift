import Foundation
@testable import OndKit
import Testing

/// Home's one line of plain language: this week's count, and an early end
/// said as exactly that.
@Suite("Home's state line")
struct HomeStateLineTests {
    /// A fixed calendar so the week boundary is the test's, not the machine's.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Mid-week UTC — noon on Thursday 2026-04-23 — so same-day neighbours
    /// stay inside the ISO week and a seven-day step lands outside it.
    private static let now = Date(timeIntervalSince1970: 1_776_945_600)

    private func line(_ history: [SessionRecord]) -> String? {
        HomeStateLine.line(history: history, now: Self.now, calendar: Self.calendar)
    }

    @Test("An empty history says nothing at all")
    func nothingYetSaysNothing() {
        #expect(line([]) == nil)
    }

    @Test("The first session ever is said as the first")
    func theFirstSessionIsOnTheRecord() {
        #expect(line([HomeFixtures.session("box-breathing", at: Self.now)]) ==
            "Your first session is on the record.")
    }

    @Test("A first week is counted as a first week")
    func aFirstWeekIsCountedAsOne() {
        let week = (0 ..< 3).map {
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(Double($0) * -3600)
            )
        }

        #expect(line(week) == "Three sessions in your first week.")
    }

    @Test("Small counts are spelled out, large ones stay digits")
    func countsAreSpelledToNine() {
        #expect(HomeStateLine.spelled(4) == "Four")
        #expect(HomeStateLine.spelled(9) == "Nine")
        #expect(HomeStateLine.spelled(10) == "10")
    }

    @Test("History wholly outside this week reads as a quiet week")
    func aQuietWeekIsSaidPlainly() {
        let lastWeek = [HomeFixtures.session(
            "box-breathing",
            at: Self.now.addingTimeInterval(-7 * 86400)
        )]

        #expect(line(lastWeek) == "Nothing this week yet.")
    }

    @Test("One finished session is counted in words")
    func oneSessionCountsInWords() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(history) == "One session this week.")
    }

    @Test("Several finished sessions are counted, and nothing more is said")
    func finishedSessionsAreJustCounted() {
        let week = (0 ..< 3).map {
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(Double($0) * -3600)
            )
        } + [HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400))]

        #expect(line(week) == "Three sessions this week.")
    }

    @Test("The week's one session ending early folds into a single sentence")
    func aLoneEarlyEndIsOneSentence() {
        let week = [
            HomeFixtures.session("box-breathing", at: Self.now, completed: false),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(week) == "One session this week, ended early — recorded as it happened.")
    }

    @Test("One early end among several is stated as the record it is")
    func oneEarlyEndIsStated() {
        let week = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-3600)),
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(-7200),
                completed: false
            ),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-10800)),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(week) ==
            "Four sessions this week. One you ended early — recorded as it happened.")
    }

    @Test("Several early ends pluralise the record")
    func severalEarlyEndsPluralise() {
        let week = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(-3600),
                completed: false
            ),
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(-7200),
                completed: false
            ),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(week) ==
            "Three sessions this week. Two you ended early — recorded as they happened.")
    }

    /// The calendar's week is half-open: a record stamped exactly on the
    /// boundary belongs to the week it starts, and must not count twice.
    @Test("A session stamped exactly on the week's end belongs to the next week")
    func theWeekIsHalfOpen() {
        // Monday 2026-04-27 00:00 UTC — the ISO week containing `now` ends
        // exactly here.
        let boundary = Date(timeIntervalSince1970: 1_777_248_000)

        #expect(line([HomeFixtures.session("box-breathing", at: boundary)]) ==
            "Nothing this week yet.")
    }

    @Test("Last week's early end does not haunt this week's line")
    func onlyThisWeeksSessionsAreCounted() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(-8 * 86400),
                completed: false
            ),
        ]

        #expect(line(history) == "One session this week.")
    }
}
