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

    /// A return needs something to return from, so a lone session is the first
    /// session and never a return, however old the install is.
    @Test("The first session ever is said as the first")
    func theFirstSessionIsOnTheRecord() {
        #expect(line([HomeFixtures.session("box-breathing", at: Self.now)]) ==
            "Your first session is recorded.")
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

        #expect(line(week) == "One session this week, ended early.")
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
            "Four sessions this week. One you ended early.")
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
            "Three sessions this week. Two you ended early.")
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

    @Test("A session after a fortnight away is said as a return, not as a count")
    func aReturnIsSaidAsAReturn() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-14 * 86400)),
        ]

        #expect(line(history) == "Your first session back is recorded.")
    }

    /// The threshold is exact, so the day below it must read as an ordinary
    /// week. docs/product/home-sentence.md argues the number.
    @Test("Thirteen days away is not yet a return")
    func thirteenDaysIsNotAReturn() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-13 * 86400)),
        ]

        #expect(line(history) == "One session this week.")
    }

    @Test("A return that ended early still says so")
    func aReturnVolunteersItsEarlyEnd() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now, completed: false),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-30 * 86400)),
        ]

        #expect(line(history) ==
            "Your first session back, ended early.")
    }

    /// Whole calendar days, not elapsed time: 01:00 is 14 days after 23:00 a
    /// fortnight earlier, though barely 13 days of clock separate them.
    @Test("The gap is counted in days, not in hours")
    func theGapIsCountedInDays() {
        // Monday 2026-04-20 01:00 UTC, inside this week, and Monday
        // 2026-04-06 23:00 UTC, fourteen calendar days before it.
        let lone = Date(timeIntervalSince1970: 1_776_646_800)
        let history = [
            HomeFixtures.session("box-breathing", at: lone),
            HomeFixtures.session("box-breathing", at: Date(timeIntervalSince1970: 1_775_516_400)),
        ]

        #expect(line(history) == "Your first session back is recorded.")
    }

    @Test("A second session this week takes the line back from the return")
    func aCountOutranksAReturn() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-3600)),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-30 * 86400)),
        ]

        #expect(line(history) == "Two sessions this week.")
    }

    /// A broken week says nothing of its own by decision, not by omission:
    /// naming the gap would be the app keeping score. See
    /// docs/product/home-sentence.md.
    @Test("A week with a gap in it reads as the week it is")
    func aBrokenWeekIsJustCounted() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-3 * 86400)),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(history) == "Two sessions this week.")
    }

    @Test("A broken week that also ended a session early keeps the early end")
    func aBrokenWeekStillVolunteersAnEarlyEnd() {
        let history = [
            HomeFixtures.session("box-breathing", at: Self.now, completed: false),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-3 * 86400)),
            HomeFixtures.session("box-breathing", at: Self.now.addingTimeInterval(-8 * 86400)),
        ]

        #expect(line(history) ==
            "Two sessions this week. One you ended early.")
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
