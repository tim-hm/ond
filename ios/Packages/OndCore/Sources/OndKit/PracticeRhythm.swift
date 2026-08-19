import Foundation

/// The last four weeks of practice, one bucket per local day.
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

        /// Sessions that day, whatever they were for.
        public let sessions: Int

        /// Milliseconds breathed that day. The chart keeps the stored unit until
        /// it draws, so two short sessions are summed before any rounding occurs.
        public let durationMilliseconds: Int

        public var id: Date {
            date
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

    /// Sessions in the window by what each was for, and the whole of what the
    /// split is kept for.
    ///
    /// A window total rather than a count per day, which is what this carried
    /// while the chart was going to stack its bars by goal. It is not, and the
    /// reason is measured: the five goal accents separate by as little as ΔE 7.1
    /// in the light appearance and 7.6 in the dark one against a floor of 15 for
    /// a reader with full colour vision — they walk one arc of the wheel so that
    /// they read as one palette wherever a *word* carries the identity beside
    /// them, and a stacked bar has no word. So the chart is one hue and names
    /// its goal in a sentence, and a per-day split would be twenty-eight
    /// dictionaries nothing reads.
    public let goalTotals: [TechniqueGoal: Int]

    /// Sessions represented by the chart's four-week window.
    public let sessions: Int

    /// Whole minutes represented by the chart, rounded after the sessions are
    /// summed so short practices do not each lose their remainder.
    public let minutes: Int

    /// How many days in the window carry a session at all.
    public var daysPractised: Int {
        days.filter { $0.sessions > 0 }.count
    }

    /// The longest day, which is the chart's y ceiling. At least one
    /// millisecond, so an empty window never creates a zero divisor.
    public var busiestDayDurationMilliseconds: Int {
        max(days.map(\.durationMilliseconds).max() ?? 0, 1)
    }

    /// What most of the window was for, or nil where nothing was breathed.
    ///
    /// Ties break on `TechniqueGoal`'s own order, so a fortnight split evenly
    /// between two goals names the same one both times somebody looks.
    public var leadingGoal: TechniqueGoal? {
        TechniqueGoal.allCases
            .filter { goalTotals[$0] != nil }
            .max { goalTotals[$0, default: 0] < goalTotals[$1, default: 0] }
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
    ///   - sessions: every session on this device, in any order. Anything
    ///     outside the window is discarded here rather than by the caller.
    ///   - goals: what each technique is for, keyed by slug — the caller's join
    ///     against everything currently breathable, the catalogue *and*
    ///     whatever this person composed. A slug with no entry still contributes
    ///     to the bars and figures; only the optional goal caption ignores it,
    ///     because filing it under a guessed goal would make that sentence wrong.
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

        // The window as two instants, so a session outside it is rejected by a
        // date comparison rather than by a calendar computation. This walks a
        // whole install's history on every fold and `startOfDay(for:)` is not
        // cheap; a person three years in has a thousand records and
        // twenty-eight of the days they could land on.
        let opens = dates.first ?? today
        let closes = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        var sessionsByDay: [Date: Int] = [:]
        var durationByDay: [Date: Int] = [:]
        var counted: [TechniqueGoal: Int] = [:]
        var sessionCount = 0
        var durationMilliseconds = 0
        for session in sessions {
            guard session.startedAt >= opens, session.startedAt < closes else { continue }

            let day = calendar.startOfDay(for: session.startedAt)
            sessionsByDay[day, default: 0] += 1
            durationByDay[day, default: 0] += session.durationMs
            if let goal = goals[session.techniqueSlug] {
                counted[goal, default: 0] += 1
            }
            sessionCount += 1
            durationMilliseconds += session.durationMs
        }

        days = dates.map {
            Day(
                date: $0,
                sessions: sessionsByDay[$0] ?? 0,
                durationMilliseconds: durationByDay[$0] ?? 0
            )
        }
        goalTotals = counted
        self.sessions = sessionCount
        minutes = durationMilliseconds / 60000
    }
}
