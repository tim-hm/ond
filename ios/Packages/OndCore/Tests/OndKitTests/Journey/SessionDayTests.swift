import Foundation
@testable import OndKit
import Testing

/// The history log's fold: which local day a session lands under, what the
/// header over it says, and how long that day ran.
@Suite("The history log's days")
struct SessionDayTests {
    /// A fixed calendar in a fixed zone, so "the local day" is a claim this
    /// suite makes rather than one the machine running it does.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar
    }

    private static func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            fatalError("2026-08-\(day) \(hour):\(minute) is not a date")
        }
        return date
    }

    /// Noon on the twelfth — the moment every header here is named against.
    private static let now = moment(12, 12)

    /// Every day the records hold, which is the page asked to cover all of them.
    private func days(_ sessions: [SessionRecord]) -> [SessionDay] {
        SessionDay.wholeDays(
            of: sessions,
            coveringAtLeast: sessions.count,
            calendar: Self.calendar,
            relativeTo: Self.now
        )
    }

    @Test("Nothing breathed groups into no days")
    func nothingGroupsIntoNothing() {
        #expect(days([]).isEmpty)
    }

    /// Four practices before lunch are four rows under one header, which is the
    /// whole reason the log groups rather than dates every row.
    @Test("One day's sessions land under one header, in the order given")
    func oneDayHoldsItsSessions() {
        let morning = [
            HomeFixtures.session("box-breathing", at: Self.moment(12, 11)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 9)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
        ]
        let grouped = days(morning)

        #expect(grouped.count == 1)
        #expect(grouped[0].sessions == morning)
    }

    /// A session at half past eleven at night belongs to the evening the person
    /// was living in, not to the next day in UTC.
    @Test("A late session stays on its own local day")
    func aLateSessionKeepsItsDay() {
        let grouped = days([
            HomeFixtures.session("box-breathing", at: Self.moment(11, 23, 30)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
        ])

        #expect(grouped.count == 2)
        #expect(grouped[0].date == Self.calendar.startOfDay(for: Self.moment(11, 0)))
        #expect(grouped[1].date == Self.calendar.startOfDay(for: Self.moment(12, 0)))
    }

    @Test("The two days somebody can place without reading a date are named")
    func todayAndYesterdayAreNamed() {
        let grouped = days([
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(11, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(10, 8)),
        ])

        #expect(grouped[0].title == "Today")
        #expect(grouped[1].title == "Yesterday")

        let older = grouped[2].title
        #expect(older != "Today")
        #expect(older != "Yesterday")
        #expect(older.contains("10"))
    }

    /// The header sums the day before rounding. Two practices of a hundred
    /// seconds are three minutes together; rounded first they would be four.
    @Test("A day totals its sessions, and a short one still reads as a minute")
    func aDayTotalsItsPractice() {
        let twoShort = days([
            HomeFixtures.session("box-breathing", at: Self.moment(12, 9), lasting: .seconds(100)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8), lasting: .seconds(100)),
        ])
        #expect(twoShort[0].minutes == 3)

        let brief = days([
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8), lasting: .seconds(20)),
        ])
        #expect(brief[0].minutes == 1)
    }

    /// A page boundary must not fall inside a day: the header states that
    /// day's total, so half a day under it would understate the practice and
    /// then change when the next page landed.
    @Test("A page takes whole days, never part of one")
    func aPageKeepsItsDaysWhole() {
        let records = [
            HomeFixtures.session("box-breathing", at: Self.moment(12, 9)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(11, 9)),
            HomeFixtures.session("box-breathing", at: Self.moment(11, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(10, 8)),
        ]

        // Three rows would cut the eleventh in half; the whole day comes.
        let page = SessionDay.wholeDays(
            of: records,
            coveringAtLeast: 3,
            calendar: Self.calendar,
            relativeTo: Self.now
        )

        #expect(page.count == 2)
        #expect(page.map(\.sessions.count) == [2, 2])
    }

    /// The page is why the fold streams: it must stop at the day that fills it
    /// rather than grouping an install's whole history first and slicing after.
    @Test("A full page never reads past the day that filled it")
    func aFullPageStopsReading() {
        var read = 0
        let records = (0 ..< 20).map { index in
            HomeFixtures.session("box-breathing", at: Self.moment(12 - index / 2, 9))
        }
        let counted = records.lazy.map { record -> SessionRecord in
            read += 1
            return record
        }

        let page = SessionDay.wholeDays(
            of: counted,
            coveringAtLeast: 2,
            calendar: Self.calendar,
            relativeTo: Self.now
        )

        #expect(page.count == 1)
        // The two of the twelfth, and the first of the eleventh — the record
        // that proves the day is over.
        #expect(read == 3)
    }

    @Test("Asking for more rows than there are yields every day")
    func awholePageIsEveryDay() {
        let records = [
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(11, 8)),
        ]

        let page = SessionDay.wholeDays(
            of: records,
            coveringAtLeast: 50,
            calendar: Self.calendar,
            relativeTo: Self.now
        )

        #expect(page.count == 2)
    }
}
