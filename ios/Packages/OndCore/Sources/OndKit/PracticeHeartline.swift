import Foundation

/// What your heart was doing around the last few sessions you practised.
///
/// The sibling of `PracticeRhythm`, and deliberately a different question: that
/// one counts what you did, this one is the one thing on the screen your body
/// answered rather than you. It is context, never a score — there is no target
/// here, no direction that counts as progress, and the caption says so out loud.
///
/// **Nothing is stored.** Every number in it is read from Health at the moment
/// the card is drawn and discarded with the view, which is the same promise
/// `PulseTrace` makes about a live session: a heart rate is health data, and the
/// journal that reaches the server is not where it goes. That is why this type
/// takes readings as a parameter instead of holding a store — the fold is
/// testable and the data is nobody's to keep.
///
/// **A silent practice is still a mark.** A session breathed without a watch on
/// gets a bar with no reading rather than being dropped, on `PracticeRhythm`'s
/// reasoning about missed days: a chart drawn only over the sessions that
/// answered shows an unbroken run of readings, which is a claim about coverage
/// nobody made. Absence is drawn, never zero-filled.
///
/// Pure, and given the moment "now" rather than reading a clock, so every rule
/// here is testable at any time of day.
public struct PracticeHeartline: Sendable, Equatable {
    /// One practice, and what the heart was doing across it.
    public struct Mark: Sendable, Equatable, Identifiable {
        /// The session's own id, so a redraw keeps each bar in place.
        public let id: UUID

        /// The average across the practice and its settle, rounded to whole
        /// beats — or nil where Health had nothing, which is a watch that was
        /// not on a wrist. Whole beats because a tenth of a beat a minute is
        /// precision this measurement does not have and nobody would act on.
        public let beatsPerMinute: Int?

        /// Whether this practice was today, in the reader's own calendar.
        public let isToday: Bool
    }

    /// How many practices the card draws. Ten: enough that a shape is visible,
    /// few enough that each bar stays wide enough to be a bar on a phone.
    public static let bars = 10

    /// How far back a practice may be and still be drawn, in days.
    ///
    /// Taken from `PracticeRhythm` rather than restated: the two cards sit on
    /// the same screen answering about the same stretch of somebody's life, and
    /// two literals are how they come to mean two different months.
    public static let window = PracticeRhythm.window

    /// How long after a practice ends the read keeps looking.
    ///
    /// A watch outside a workout samples every few minutes, so a five-minute
    /// practice can contain no sample at all; three minutes of settle roughly
    /// doubles the chance of catching one and is still recognisably part of the
    /// same sitting. There is deliberately no lead-in: the minutes spent walking
    /// to the sofa are not the practice, and averaging them in would make every
    /// bar the walk rather than the breathing.
    public static let settle: Duration = .seconds(180)

    /// How many readings it takes before the shape is worth drawing at all.
    ///
    /// Two, because one bar is not a trend and drawing it invites somebody to
    /// read a number as a verdict. Below this the card is not mounted — there is
    /// no empty state, because "your watch was not on" is not news.
    public static let minimumReadings = 2

    /// The practices to draw, oldest first — including the ones Health had
    /// nothing for.
    public let marks: [Mark]

    /// The sessions a heartline is drawn over: recent practice, most recent
    /// ``bars`` of it, oldest first.
    ///
    /// Separate from the initialiser so the caller can ask Health about exactly
    /// these windows and nothing else. That ordering is the point — the read is
    /// scoped to what will be drawn rather than to a range of somebody's life.
    ///
    /// False starts are not practice, on `SessionRecord.isFalseStart`'s rule:
    /// a mistap is not a sitting, and a bar for the eight seconds before
    /// somebody put the phone down would be a reading of them noticing.
    public static func practices(
        in history: [SessionRecord],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SessionRecord] {
        guard let earliest = calendar.date(byAdding: .day, value: -(window - 1), to: now) else {
            return []
        }
        let from = calendar.startOfDay(for: earliest)

        return history
            .filter { !$0.isFalseStart && $0.startedAt >= from && $0.startedAt <= now }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(bars)
            .reversed()
    }

    /// The span of time a practice's heart rate is read over: the session
    /// itself, plus ``settle``.
    public static func heartWindow(around practice: SessionRecord) -> DateInterval {
        DateInterval(
            start: practice.startedAt,
            end: practice.startedAt.addingTimeInterval(
                (practice.duration + settle).seconds
            )
        )
    }

    /// - Parameters:
    ///   - practices: what ``practices(in:now:calendar:)`` answered.
    ///   - readings: whatever Health returned for those windows, in any order
    ///     and with any of them missing.
    ///   - now: the moment "today" is measured from.
    ///   - calendar: the reader's own, so "today" is their day.
    ///
    /// Readings are matched to practices **by window, never by position**. A
    /// batch read is sparse — a window with no samples yields no entry — so a
    /// positional zip silently shifts every later reading onto the wrong
    /// session, and the result looks entirely plausible.
    public init(
        practices: [SessionRecord],
        readings: [WindowedQuantity],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        // Keyed on the whole window rather than on its start, which is what
        // `WindowedQuantity` tells its callers to match on: a reading answered
        // for a window of a different length is a reading of a different
        // session, whatever moment it began at.
        let byWindow = Dictionary(
            readings.map { ($0.window, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        marks = practices.map { practice in
            Mark(
                id: practice.id,
                beatsPerMinute: byWindow[Self.heartWindow(around: practice)]
                    .map { Int($0.rounded()) },
                isToday: calendar.isDate(practice.startedAt, inSameDayAs: now)
            )
        }
    }

    /// How many of the drawn practices actually carry a reading.
    public var readingCount: Int {
        marks.count { $0.beatsPerMinute != nil }
    }

    /// Whether there is enough here to be worth a card.
    public var isWorthDrawing: Bool {
        readingCount >= Self.minimumReadings
    }

    /// The quietest and busiest readings drawn, or nil where none were read.
    public var range: ClosedRange<Int>? {
        let rates = marks.compactMap(\.beatsPerMinute)
        guard let lowest = rates.min(), let highest = rates.max() else { return nil }
        return lowest ... highest
    }

    /// Where `mark` sits between the quietest and busiest readings drawn, from 0
    /// to 1 — or nil where it has no reading of its own.
    ///
    /// **Range-normalised rather than measured from zero.** A resting heart
    /// spans maybe fifteen beats across a fortnight, and against a zero baseline
    /// fifteen beats out of sixty is a chart of ten identical bars. The scale is
    /// therefore relative, and the caption states the two ends so nobody reads a
    /// tall bar as a large number.
    ///
    /// A heart that was level across every practice comes back at 0.5 rather
    /// than 0 or 1: with nothing to separate, the honest drawing is a row of
    /// equal bars at half height, not a row of empty ones.
    public func fraction(of mark: Mark) -> Double? {
        guard let rate = mark.beatsPerMinute, let range else { return nil }
        return Self.fraction(of: rate, in: range)
    }

    /// The same arithmetic against a range the caller is already holding — what
    /// a plot drawing ten bars uses, so the range is derived once rather than
    /// re-folded out of every mark.
    public static func fraction(of rate: Int, in range: ClosedRange<Int>) -> Double {
        guard range.lowerBound < range.upperBound else { return 0.5 }

        return Double(rate - range.lowerBound)
            / Double(range.upperBound - range.lowerBound)
    }
}
