import Foundation

/// The practice totals Home and Progress count from sessions on this device.
///
/// Computed locally and not fetched, because the app is offline-first: the tab
/// has to be fully populated in airplane mode, and a screen that waits on a
/// request to show somebody their own history is a screen that is sometimes
/// blank for no reason they can see.
///
/// The **streak** is the one number the server also computes — it has to, for
/// the leaderboard — so those two definitions have to agree exactly. A drift
/// would show a person one streak on their phone and another on a board.
/// Everything else here is this device's own fold, `daysPractised` included:
/// nothing on a board is drawn from it, so nothing on the wire carries it. The
/// rules both sides implement for the streak:
///
/// - A day is a **local** calendar day. A session at 23:30 belongs to the day
///   the person was living in, not to tomorrow in UTC.
/// - The **best** streak is the longest run of consecutive days there has ever
///   been. It never decreases.
/// - The **current** streak is a run ending today *or yesterday*. A streak is
///   not broken until a whole local day has passed with no session, so somebody
///   who has not breathed yet this morning has not lost anything.
public struct JourneyStats: Sendable, Equatable {
    public let sessions: Int
    /// Whole minutes, rounded down, from the summed milliseconds — so a hundred
    /// short sessions do not each lose their remainder.
    public let minutes: Int

    /// How many distinct local days carry a session — the dosed quantity, as
    /// against the consecutive one beside it.
    ///
    /// The number the evidence is actually about. In the trial the daily
    /// exercise comes from, what people got out of the month scaled with how
    /// many days they practised rather than with how long any one sitting ran,
    /// and no result anywhere in that literature turns on doing them
    /// back-to-back. A streak is a device for keeping the days coming; this is
    /// the thing the device is *for*, which is why it leads and why, unlike a
    /// streak, it only ever goes up.
    public let daysPractised: Int

    public let currentStreakDays: Int
    public let bestStreakDays: Int

    /// What somebody has before their first session — the fold itself over no
    /// sessions, rather than a hand-written set of zeros that could fall out of
    /// step with it.
    public static let none = Self(sessions: [])

    /// Where this practice stands, or nil before the first session.
    ///
    /// The streak is the living number and this is the settled one: a streak
    /// pauses and picks up again, a stage only ever arrives. Nothing a person
    /// stops doing can take one back — which is what makes it safe to show
    /// beside a streak that has paused.
    public var stage: PracticeStage? {
        .held(atSessionCount: sessions)
    }

    /// The streak, said in a way nobody has to brace for.
    ///
    /// The product's copy rule is a rule, not a preference — celebrate
    /// consistency, never pressure — so it lives beside the numbers it reads
    /// rather than in a view the app target has no test bundle to pin.
    public var streakHeadline: String {
        switch currentStreakDays {
        case 0: bestStreakDays == 0 ? "Ready when you are" : "Your streak is paused"
        case 1: "One day in"
        case let days: "\(days) days in a row"
        }
    }

    /// The best streak is always there to fall back on, which is the point of
    /// keeping it: a run that has paused is still a run somebody did.
    public var streakDetail: String {
        if currentStreakDays == 0 {
            return bestStreakDays == 0
                ? "Your first session starts the count."
                : "Your longest run was \(dayCount(bestStreakDays)). One session picks it up again."
        }

        return currentStreakDays >= bestStreakDays
            ? "That's your longest run yet."
            : "Your longest run is \(dayCount(bestStreakDays))."
    }

    private func dayCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "day" : "days")"
    }

    /// - Parameters:
    ///   - sessions: every session on this device, in any order.
    ///   - calendar: carries the time zone the days are counted in. The default
    ///     follows the device, so flying somewhere changes the answer — which is
    ///     correct, and is the same reason the server takes the offset per
    ///     request rather than storing it.
    ///   - now: the moment "today" is measured from. A parameter so a test can
    ///     name a day rather than wait for one.
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
