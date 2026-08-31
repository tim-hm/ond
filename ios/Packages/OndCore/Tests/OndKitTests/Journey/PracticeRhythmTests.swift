import Foundation
@testable import OndKit
import Testing

/// The chart's fold: which local day a session lands in, how far back the window
/// reaches, and when there is enough to be worth drawing.
@Suite("The practice rhythm")
struct PracticeRhythmTests {
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

    /// Noon on the twelfth — the moment every window here ends at.
    private static let now = moment(12, 12)

    /// Nine in the morning, `back` days before `now`. Date arithmetic rather
    /// than a day number, so a window reaching into the previous month is
    /// counted by the calendar rather than by hand.
    private static func daysAgo(_ back: Int) -> Date {
        guard let date = calendar.date(byAdding: .day, value: -back, to: moment(12, 9)) else {
            fatalError("\(back) days before 2026-08-12 is not a date")
        }
        return date
    }

    private static let goals: [TechniqueSlug: TechniqueGoal] = [
        "box-breathing": .calm,
        "four-seven-eight": .sleep,
        "bellows-breath": .energy,
    ]

    private func rhythm(_ sessions: [SessionRecord]) -> PracticeRhythm {
        PracticeRhythm(
            sessions: sessions,
            goals: Self.goals,
            calendar: Self.calendar,
            now: Self.now
        )
    }

    // MARK: the window

    /// Every day in it, empty ones included: their absence is the information a
    /// rhythm is supposed to carry, and a chart drawn over only the days
    /// somebody practised shows an unbroken run whatever the gaps were.
    @Test("The window is four weeks of days, today last")
    func theWindowIsWholeAndOrdered() {
        let days = rhythm([]).days

        #expect(days.count == PracticeRhythm.window)
        #expect(days.last?.date == Self.calendar.startOfDay(for: Self.now))
        #expect(days.map(\.date) == days.map(\.date).sorted())
        #expect(days.allSatisfy { $0.sessions == 0 && $0.durationMilliseconds == 0 })
    }

    @Test("A session older than the window is not counted")
    func theWindowHasAFloor() {
        let inside = HomeFixtures.session("box-breathing", at: Self.daysAgo(27))
        let outside = HomeFixtures.session("box-breathing", at: Self.daysAgo(28))

        #expect(rhythm([inside, outside]).days.first?.sessions == 1)
        #expect(rhythm([inside, outside]).days.map(\.sessions).reduce(0, +) == 1)
    }

    /// The one case a UTC bucket gets wrong. Half past eleven at night belongs
    /// to the day the person was living in, which is `JourneyStats`' rule and has
    /// to be this one too — two screens counting the same session on different
    /// days would be a chart disagreeing with the streak above it.
    @Test("A session at 23:30 belongs to the day it was breathed in")
    func lateSessionsStayOnTheirOwnDay() {
        let late = HomeFixtures.session("box-breathing", at: Self.moment(11, 23, 30))
        let days = rhythm([late]).days

        #expect(days.last?.sessions == 0)
        #expect(days.dropLast().last?.date == Self.calendar.startOfDay(for: Self.moment(11, 12)))
        #expect(days.dropLast().last?.sessions == 1)
    }

    // MARK: the split

    @Test("A day counts every session breathed in it")
    func aDayCountsItsSessions() throws {
        let rhythm = rhythm([
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 9)),
            HomeFixtures.session("bellows-breath", at: Self.moment(12, 10)),
        ])

        let today = try #require(rhythm.days.last)
        #expect(today.sessions == 3)
        #expect(today.durationMilliseconds == 360_000)
        #expect(rhythm.goalTotals == [.calm: 2, .energy: 1])
        #expect(rhythm.sessions == 3)
        #expect(rhythm.minutes == 6)
    }

    /// The map is the caller's join against everything breathable, not just the
    /// catalogue. Somebody practising only an exercise they wrote was seeing an
    /// empty chart beside tiles counting their days.
    @Test("An exercise somebody wrote counts like any other")
    func authoredExercisesAreCounted() {
        let mine = PracticeRhythm(
            sessions: [
                HomeFixtures.session("mine", at: Self.moment(10, 8)),
                HomeFixtures.session("box-breathing", at: Self.moment(11, 8)),
                HomeFixtures.session("mine", at: Self.moment(12, 8)),
            ],
            goals: Self.goals.merging(["mine": .reset]) { _, mine in mine },
            calendar: Self.calendar,
            now: Self.now
        )

        #expect(mine.daysPractised == 3)
        #expect(mine.leadingGoal == .reset)
    }

    /// History outlives catalogue entries. The record still counts as practice;
    /// only the goal caption declines to guess what it was for.
    @Test("An unresolved exercise still counts everywhere except the goal split")
    func anUnresolvableSlugStillCounts() {
        let orphan = HomeFixtures.session("an-exercise-nobody-ships", at: Self.moment(12, 8))
        let orphaned = rhythm([orphan])

        #expect(orphaned.days.last?.sessions == 1)
        #expect(orphaned.days.last?.durationMilliseconds == 120_000)
        #expect(orphaned.sessions == 1)
        #expect(orphaned.minutes == 2)
        #expect(orphaned.goalTotals.isEmpty)
        #expect(orphaned.leadingGoal == nil)
    }

    // MARK: what the window was mostly for

    @Test("Nothing breathed leads with no goal")
    func nothingLeadsWithNoGoal() {
        #expect(rhythm([]).leadingGoal == nil)
    }

    @Test("The goal with the most sessions across the window leads")
    func theBusiestGoalLeads() {
        #expect(rhythm([
            HomeFixtures.session("box-breathing", at: Self.moment(9, 8)),
            HomeFixtures.session("four-seven-eight", at: Self.moment(10, 22)),
            HomeFixtures.session("four-seven-eight", at: Self.moment(11, 22)),
        ]).leadingGoal == .sleep)
    }

    /// A fortnight split evenly has to name the same goal both times somebody
    /// looks, so the tie breaks on the enum's order rather than on whichever
    /// key the dictionary happened to hold first.
    @Test("A tie breaks on the goals' own order")
    func aTieBreaksOnEnumOrder() {
        #expect(rhythm([
            HomeFixtures.session("four-seven-eight", at: Self.moment(10, 22)),
            HomeFixtures.session("box-breathing", at: Self.moment(11, 8)),
        ]).leadingGoal == .calm)
    }

    // MARK: how many days carried practice

    @Test("Nothing breathed is no days practised")
    func nothingIsNoDays() {
        #expect(rhythm([]).daysPractised == 0)
    }

    /// However many sessions one day carried, it is still one day: the figure
    /// counts days, which is the number the trial's outcomes scaled with.
    @Test("One day counts once, at any session count")
    func oneDayCountsOnce() {
        let sameDay = (8 ... 11)
            .map { HomeFixtures.session("box-breathing", at: Self.moment(12, $0)) }

        #expect(rhythm(sameDay).daysPractised == 1)
    }

    /// The y ceiling follows time rather than visit count, and never reaches
    /// zero where the chart would divide by it.
    @Test("The longest day is the chart ceiling, and never zero")
    func theLongestDayIsTheCeiling() {
        #expect(rhythm([]).busiestDayDurationMilliseconds == 1)
        #expect(rhythm([
            HomeFixtures.session("box-breathing", at: Self.moment(9, 8)),
            HomeFixtures.session("box-breathing", at: Self.moment(12, 8)),
            HomeFixtures.session("bellows-breath", at: Self.moment(12, 9)),
        ]).busiestDayDurationMilliseconds == 240_000)
    }
}
