import Foundation

/// The last four weeks of practice, one bucket per local day, split by what each
/// session was for.
///
/// The shape a chart needs, folded where it can be tested. `JourneyStats` counts
/// the same sessions and answers a different question — how many days, how long
/// a run — and neither wants the other's arithmetic: a streak is a scalar and
/// this is a series.
///
/// A day is a **local** calendar day, on `JourneyStats`' rule and for the same
/// reason: a session at 23:30 belongs to the day the person was living in, not
/// to tomorrow in UTC. The calendar and the moment "now" is measured from both
/// arrive as parameters so a test can name a day rather than wait for one.
public struct PracticeRhythm: Sendable, Equatable {
    /// One local day's practice.
    public struct Day: Sendable, Equatable, Identifiable {
        /// The start of the local day, which is what the chart plots against.
        public let date: Date

        /// Sessions that day, by what each was for. A goal absent from the
        /// dictionary had no session, which is the same claim as zero and one
        /// fewer entry to carry.
        public let counts: [TechniqueGoal: Int]

        public var id: Date {
            date
        }

        /// Sessions that day, whatever they were for.
        public var total: Int {
            counts.values.reduce(0, +)
        }

        /// How many sessions that day were for `goal` — nothing rather than a
        /// zero-height bar where there were none.
        public func count(of goal: TechniqueGoal) -> Int {
            counts[goal] ?? 0
        }
    }

    /// How many days the chart looks back over, today included. Four weeks: long
    /// enough that a weekly rhythm shows up as one, short enough that the bars
    /// stay wide enough to read on a phone.
    public static let window = 28

    /// Every day in the window, oldest first — including the ones with nothing
    /// in them.
    ///
    /// The empty days are in rather than out because their absence is the
    /// information: a bar chart over only the days somebody practised draws an
    /// unbroken run whatever the gaps were, which is the one thing a rhythm is
    /// supposed to show. It also fixes the axis, so the chart does not rescale
    /// under somebody between two sessions.
    public let days: [Day]

    /// How many days in the window carry a session at all.
    public var daysPractised: Int {
        days.filter { $0.total > 0 }.count
    }

    /// The tallest day, which is the chart's y ceiling. At least one, so a
    /// single session does not draw a bar filling the frame.
    public var busiestDay: Int {
        max(days.map(\.total).max() ?? 0, 1)
    }

    /// Whether there is enough here to be worth drawing.
    ///
    /// Two distinct days. One day of practice is a fact somebody already knows
    /// and a chart of it is a single bar in an empty frame — a graph that says
    /// less than the sentence above it while taking six times the room. Two is
    /// the first number where the drawing carries something the tiles do not:
    /// where the days sat relative to each other.
    ///
    /// A rule rather than a condition in the view, so it is pinned by a test
    /// instead of by whoever last read the screen.
    public var isWorthCharting: Bool {
        daysPractised >= 2
    }

    /// - Parameters:
    ///   - sessions: every session on this device, in any order. Anything older
    ///     than the window is discarded here rather than by the caller.
    ///   - goals: what each technique is for, keyed by slug — the caller's join
    ///     against the catalogue, because a record carries a slug and not a
    ///     goal. A slug with no entry is a session whose exercise has left the
    ///     catalogue, and it is dropped rather than counted: every bar is drawn
    ///     in a goal's colour, and a session with no goal would have to be given
    ///     one it was never breathed for.
    ///   - calendar: carries the time zone the days are counted in. The default
    ///     follows the device, so flying somewhere changes the answer — which is
    ///     correct, and is `JourneyStats`' choice too.
    ///   - now: the moment the window ends at.
    public init(
        sessions: [SessionRecord],
        goals: [String: TechniqueGoal],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        let today = calendar.startOfDay(for: now)

        // Oldest first, and `window - 1` back because today is one of the days.
        let dates = (0 ..< Self.window).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today)
        }

        var counted: [Date: [TechniqueGoal: Int]] = [:]
        for session in sessions {
            guard let goal = goals[session.techniqueSlug] else { continue }
            let day = calendar.startOfDay(for: session.startedAt)
            guard day >= dates.first ?? today, day <= today else { continue }
            counted[day, default: [:]][goal, default: 0] += 1
        }

        days = dates.map { Day(date: $0, counts: counted[$0] ?? [:]) }
    }
}
