import Foundation

/// The practice totals counted from the sessions on this device — computed
/// locally, so the tab is fully populated in airplane mode. The **streak** is
/// the one number the server also computes, and the two must agree exactly:
/// a day is a *local* calendar day, best never decreases, and the current
/// streak ends today *or yesterday* — unbroken until a whole day passes.
public struct JourneyStats: Sendable, Equatable {
    public let sessions: Int
    /// Whole minutes, rounded down, from the summed milliseconds — so a hundred
    /// short sessions do not each lose their remainder.
    public let minutes: Int

    /// How many distinct local days carry a session — the dosed quantity, and
    /// the number the evidence is actually about: in the trial the daily
    /// exercise comes from, benefit scaled with days practised, not sitting
    /// length. A streak keeps the days coming; this is what the device is
    /// *for*, which is why it leads and, unlike a streak, only ever goes up.
    public let daysPractised: Int

    public let currentStreakDays: Int
    public let bestStreakDays: Int

    /// What somebody has before their first session — the fold itself over no
    /// sessions, rather than a hand-written set of zeros that could fall out of
    /// step with it.
    public static let none = Self(sessions: [])

    /// - Parameter calendar: carries the time zone the days are counted in.
    ///   The default follows the device, so flying somewhere changes the
    ///   answer — correct, and the reason the server takes the offset per
    ///   request rather than storing it.
    /// - Parameter now: a parameter so a test can name a day, not wait for one.
    public init(
        sessions records: [SessionRecord],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        sessions = records.count
        minutes = records.reduce(0) { $0 + $1.durationMs } / 60000

        let days = Set(records.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        daysPractised = days.count

        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            let isConsecutive = previous.flatMap {
                calendar.dateComponents([.day], from: $0, to: day).day
            } == 1
            run = isConsecutive ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        bestStreakDays = best

        // `days` is ascending, so `run` is the length of the run ending on the
        // last day — the only run that can still be current.
        let today = calendar.startOfDay(for: now)
        let daysSinceLast = days.last.flatMap {
            calendar.dateComponents([.day], from: $0, to: today).day
        }
        currentStreakDays = (daysSinceLast ?? .max) <= 1 ? run : 0
    }
}
