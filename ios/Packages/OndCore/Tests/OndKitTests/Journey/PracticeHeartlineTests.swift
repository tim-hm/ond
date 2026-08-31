import Foundation
@testable import OndKit
import Testing

/// What the heart-rate card is drawn from.
///
/// The rules worth pinning are the ones that fail plausibly: a chart that
/// silently drops the practices Health had nothing for, or one that pairs a
/// reading with the wrong session, looks entirely correct on screen.
@Suite("The practice heartline")
struct PracticeHeartlineTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_000_000)

    private static let calendar = HeartFixtures.calendar

    private static func session(
        at date: Date,
        minutes: Double = 5,
        completed: Bool = true
    ) -> SessionRecord {
        HomeFixtures.session(at: date, lasting: .seconds(minutes * 60), completed: completed)
    }

    private static func heartline(
        _ practices: [SessionRecord],
        _ readings: [WindowedQuantity]
    ) -> PracticeHeartline {
        PracticeHeartline(
            practices: practices,
            readings: readings,
            now: noon,
            calendar: calendar
        )
    }

    // MARK: which practices are drawn

    @Test("At most ten practices, and the most recent ten")
    func drawsTheMostRecentTen() {
        let history = (0 ..< 15)
            .map { Self.session(at: Self.noon.addingTimeInterval(Double(-$0) * 3600)) }

        let drawn = PracticeHeartline.practices(
            in: history,
            now: Self.noon,
            calendar: Self.calendar
        )

        #expect(drawn.count == PracticeHeartline.bars)
        // Oldest first, and the oldest drawn is the tenth-most-recent session.
        #expect(drawn.first?.startedAt == Self.noon.addingTimeInterval(-9 * 3600))
        #expect(drawn.last?.startedAt == Self.noon)
    }

    /// A mistap is not a sitting, and a bar for the eight seconds before
    /// somebody put the phone down would be a reading of them noticing.
    @Test("A false start is not a practice")
    func falseStartsAreNotPractices() {
        let mistap = Self.session(at: Self.noon, minutes: 0.1, completed: false)
        let practice = Self.session(at: Self.noon.addingTimeInterval(-3600))

        let drawn = PracticeHeartline.practices(
            in: [mistap, practice],
            now: Self.noon,
            calendar: Self.calendar
        )

        #expect(drawn.map(\.id) == [practice.id])
    }

    @Test("A session older than the window is not drawn")
    func oldPracticesFallOutOfTheWindow() {
        let old = Self.session(at: Self.noon.addingTimeInterval(-40 * 86400))

        #expect(
            PracticeHeartline
                .practices(in: [old], now: Self.noon, calendar: Self.calendar)
                .isEmpty
        )
    }

    /// A clock that has run forward — a device whose time was wrong, a record
    /// synced from one — must not put a bar in the future.
    @Test("A session dated after now is not drawn")
    func futurePracticesAreIgnored() {
        let ahead = Self.session(at: Self.noon.addingTimeInterval(3600))

        #expect(
            PracticeHeartline
                .practices(in: [ahead], now: Self.noon, calendar: Self.calendar)
                .isEmpty
        )
    }

    // MARK: the window Health is asked about

    @Test("The window is the practice plus its settle, and starts when it did")
    func theWindowIsThePracticeAndItsSettle() {
        let practice = Self.session(at: Self.noon, minutes: 5)

        let window = PracticeHeartline.heartWindow(around: practice)

        #expect(window.start == Self.noon)
        #expect(window.duration == 300 + PracticeHeartline.settle.seconds)
    }

    // MARK: matching readings to practices

    /// The regression this shape exists for. The read is sparse — a window with
    /// no samples yields no entry — so zipping by position shifts every later
    /// reading onto the wrong session, and the chart looks perfectly plausible.
    @Test("Readings match by window, out of order and with one missing")
    func readingsMatchByWindowRatherThanPosition() throws {
        let first = Self.session(at: Self.noon.addingTimeInterval(-7200))
        let second = Self.session(at: Self.noon.addingTimeInterval(-3600))
        let third = Self.session(at: Self.noon)

        let heartline = try Self.heartline(
            [first, second, third],
            [HeartFixtures.reading(for: third, 72), HeartFixtures.reading(for: first, 61)]
        )

        #expect(heartline.marks.map(\.beatsPerMinute) == [61, nil, 72])
    }

    @Test("A practice Health had nothing for is still a mark")
    func aSilentPracticeIsStillDrawn() {
        let practice = Self.session(at: Self.noon)

        let heartline = Self.heartline([practice], [])

        #expect(heartline.marks.count == 1)
        #expect(heartline.marks[0].beatsPerMinute == nil)
    }

    @Test("Today is the reader's own day, not the last 24 hours")
    func todayIsALocalDay() {
        let earlier = Self.session(at: Self.noon.addingTimeInterval(-6 * 3600))
        let yesterday = Self.session(at: Self.noon.addingTimeInterval(-20 * 3600))

        let heartline = Self.heartline([yesterday, earlier], [])

        #expect(heartline.marks.map(\.isToday) == [false, true])
    }

    // MARK: whether it is worth drawing

    @Test("One reading is not a shape")
    func oneReadingIsNotWorthDrawing() throws {
        let practice = Self.session(at: Self.noon)
        let other = Self.session(at: Self.noon.addingTimeInterval(-3600))

        let heartline = try Self.heartline(
            [other, practice],
            [HeartFixtures.reading(for: practice, 64)]
        )

        #expect(heartline.readingCount == 1)
        #expect(!heartline.isWorthDrawing)
    }

    @Test("Practices with nothing read are not worth drawing")
    func nothingReadIsNotWorthDrawing() {
        let heartline = Self.heartline(
            [Self.session(at: Self.noon), Self.session(at: Self.noon.addingTimeInterval(-3600))],
            []
        )

        #expect(heartline.range == nil)
        #expect(!heartline.isWorthDrawing)
    }

    // MARK: the scale

    @Test("The quietest and busiest readings set the scale")
    func theReadingsSetTheScale() throws {
        let quiet = Self.session(at: Self.noon.addingTimeInterval(-7200))
        let middle = Self.session(at: Self.noon.addingTimeInterval(-3600))
        let busy = Self.session(at: Self.noon)

        let heartline = try Self.heartline(
            [quiet, middle, busy],
            [
                HeartFixtures.reading(for: quiet, 58),
                HeartFixtures.reading(for: middle, 63),
                HeartFixtures.reading(for: busy, 68),
            ]
        )

        #expect(heartline.range == 58 ... 68)
        #expect(heartline.fraction(of: heartline.marks[0]) == 0)
        #expect(heartline.fraction(of: heartline.marks[1]) == 0.5)
        #expect(heartline.fraction(of: heartline.marks[2]) == 1)
        #expect(heartline.isWorthDrawing)
    }

    /// With nothing to separate, the honest drawing is a row of equal bars at
    /// half height — not a row of empty ones, which is what a zero-width range
    /// produces if nobody thinks about it.
    @Test("A level heart draws half-height bars, not empty ones")
    func aLevelHeartComesBackHalfway() throws {
        let first = Self.session(at: Self.noon.addingTimeInterval(-3600))
        let second = Self.session(at: Self.noon)

        let heartline = try Self.heartline(
            [first, second],
            [HeartFixtures.reading(for: first, 62), HeartFixtures.reading(for: second, 62)]
        )

        #expect(heartline.marks.allSatisfy { heartline.fraction(of: $0) == 0.5 })
    }

    @Test("A practice with no reading has no height")
    func aSilentMarkHasNoFraction() throws {
        let read = Self.session(at: Self.noon.addingTimeInterval(-3600))
        let silent = Self.session(at: Self.noon)

        let heartline = try Self.heartline([read, silent], [HeartFixtures.reading(for: read, 62)])

        #expect(heartline.fraction(of: heartline.marks[1]) == nil)
    }

    /// Whole beats: a tenth of a beat a minute is precision this measurement
    /// does not have and nobody would act on.
    @Test("A reading is rounded to whole beats")
    func readingsAreWholeBeats() throws {
        let practice = Self.session(at: Self.noon)

        let heartline = try Self.heartline([practice], [HeartFixtures.reading(for: practice, 63.6)])

        #expect(heartline.marks[0].beatsPerMinute == 64)
    }
}
