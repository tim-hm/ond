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

    private func line(_ history: [SessionRecord]) -> String {
        HomeStateLine.line(history: history, now: Self.now, calendar: Self.calendar)
    }

    @Test("An empty history is an invitation, not a zero")
    func firstSessionInvitation() {
        #expect(line([]) == "Your first session starts the count.")
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
        #expect(line([HomeFixtures.session("box-breathing", at: Self.now)]) ==
            "One session this week.")
    }

    @Test("Several finished sessions are counted, and nothing more is said")
    func finishedSessionsAreJustCounted() {
        let week = (0 ..< 3).map {
            HomeFixtures.session(
                "box-breathing",
                at: Self.now.addingTimeInterval(Double($0) * -3600)
            )
        }

        #expect(line(week) == "3 sessions this week.")
    }

    @Test("The week's one session ending early folds into a single sentence")
    func aLoneEarlyEndIsOneSentence() {
        let week = [HomeFixtures.session("box-breathing", at: Self.now, completed: false)]

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
        ]

        #expect(line(week) ==
            "4 sessions this week. One you ended early — recorded as it happened.")
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
        ]

        #expect(line(week) ==
            "3 sessions this week. 2 you ended early — recorded as they happened.")
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
