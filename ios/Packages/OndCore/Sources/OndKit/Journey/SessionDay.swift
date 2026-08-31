import Foundation

/// One local calendar day of practice, as the history log groups it. A day is
/// the day the person was living in when the session started, on
/// `PracticeRhythm`'s rule — a session at 23:30 belongs to that evening. The
/// calendar and the moment "now" arrive as parameters so a test can name a day
/// rather than wait for one.
public struct SessionDay: Sendable, Equatable, Identifiable {
    /// The start of the local day these sessions belong to.
    public let date: Date

    /// That day's sessions, in the order they were handed over.
    public let sessions: [SessionRecord]

    /// The day's practice in whole minutes, rounded to the nearest and never
    /// below one: a header standing over rows that happened must not read zero.
    /// Stored rather than computed, because a pinned header re-reads it
    /// through every frame of a scroll.
    public let minutes: Int

    /// The day as its header names it: `Today`, `Yesterday`, then the weekday,
    /// the date and the month — `Tuesday 26 Aug`. The two nearest days are
    /// named rather than dated, because somebody places them without a date.
    /// The month is named because the log pages over a whole history, and a
    /// bare `Wednesday 12` repeats every month. Stored, as `minutes` is.
    public let title: String

    public var id: Date {
        date
    }

    /// The leading days holding `rows` sessions between them, in the order
    /// `records` arrives — newest first, where the caller hands them over that
    /// way. A day is never cut at a page boundary: its header states that
    /// day's own total. Folded one record at a time and returned as soon as
    /// the page is full, so a whole history is never walked for one screen.
    public static func wholeDays(
        of records: some Sequence<SessionRecord>,
        coveringAtLeast rows: Int,
        calendar: Calendar = .autoupdatingCurrent,
        relativeTo now: Date = .now
    ) -> [SessionDay] {
        let names = DayNames(calendar: calendar, now: now)
        var kept: [SessionDay] = []
        var counted = 0
        // Each day's sessions must arrive together, which sorting by time
        // does; the fold streams rather than grouping through a dictionary, so
        // a day reached twice would be two days carrying the same `id`.
        var openDate: Date?
        var openSessions: [SessionRecord] = []

        for record in records {
            let date = calendar.startOfDay(for: record.startedAt)

            if let closing = openDate, closing != date {
                kept.append(SessionDay(closing, openSessions, names))
                counted += openSessions.count
                if counted >= rows {
                    return kept
                }
                openSessions = []
            }

            openDate = date
            openSessions.append(record)
        }

        if let closing = openDate {
            kept.append(SessionDay(closing, openSessions, names))
        }

        return kept
    }

    private init(_ date: Date, _ sessions: [SessionRecord], _ names: DayNames) {
        self.date = date
        self.sessions = sessions
        minutes = max(1, (sessions.reduce(0) { $0 + $1.durationMs } + 30000) / 60000)
        title = names.name(date)
    }

    /// What a day is called, resolved once per fold. The two calendar
    /// computations and the format style behind a header are otherwise redone
    /// for every day on screen, every frame of the scroll they are pinned to.
    private struct DayNames {
        let today: Date
        let yesterday: Date?
        let style: Date.FormatStyle

        init(calendar: Calendar, now: Date) {
            today = calendar.startOfDay(for: now)
            yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide)
                .day()
                .month(.abbreviated)
        }

        func name(_ date: Date) -> String {
            if date == today {
                return "Today"
            }
            if date == yesterday {
                return "Yesterday"
            }
            return date.formatted(style)
        }
    }
}
