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

    public var id: Date {
        date
    }

    /// The day's practice in whole minutes, rounded to the nearest and never
    /// below one: a header standing over rows that happened must not read zero.
    public var minutes: Int {
        let total = sessions.reduce(0) { $0 + $1.durationMs }
        return max(1, (total + 30000) / 60000)
    }

    /// The day as its header names it: `Today`, `Yesterday`, then the weekday
    /// and the date — `Tuesday 26`. Named rather than dated for the two days
    /// somebody can place without reading one.
    public func title(
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if date == today {
            return "Today"
        }
        if date == calendar.date(byAdding: .day, value: -1, to: today) {
            return "Yesterday"
        }

        return date.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide)
                .day()
        )
    }

    /// Every day carrying practice, in the order `records` arrives — newest
    /// first, where the caller hands them over that way — with each day's own
    /// sessions keeping that order under it.
    public static func grouped(
        _ records: some Sequence<SessionRecord>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SessionDay] {
        var order: [Date] = []
        var byDay: [Date: [SessionRecord]] = [:]

        for record in records {
            let day = calendar.startOfDay(for: record.startedAt)
            if byDay[day] == nil {
                order.append(day)
            }
            byDay[day, default: []].append(record)
        }

        return order.map { SessionDay(date: $0, sessions: byDay[$0] ?? []) }
    }
}
