import Foundation

/// What the coach may know about one heart metric: how it has run this week,
/// and — with enough evidence — how that compares to the weeks before.
///
/// Whole numbers on purpose. The product decision is that the coach sees coarse
/// trends, never readings: a mean rounded to the beat or the millisecond is
/// enough to shape guidance, and precision beyond that only makes the summary
/// look like a diagnosis.
public struct HealthSnapshot: Sendable, Equatable {
    /// The last seven days' mean, rounded to a whole unit.
    public let sevenDayMean: Int

    /// How the last seven days sit against the weeks before them — positive is
    /// higher than baseline. Nil when the series is too thin to support a
    /// trend; see `HealthSummaryBuilder`.
    public let trendFromBaseline: Int?

    public init(sevenDayMean: Int, trendFromBaseline: Int?) {
        self.sevenDayMean = sevenDayMean
        self.trendFromBaseline = trendFromBaseline
    }

    /// The mean as prose — "about 62 bpm", never "62 bpm".
    ///
    /// "About" is load-bearing and matches the server's own briefing copy: this
    /// is a rounded weekly mean, and a bare number reads as a reading somebody
    /// took. Nothing in this app is entitled to present a health figure that
    /// way.
    public func mean(in unit: HealthUnit) -> String {
        "about \(sevenDayMean) \(unit.after(sevenDayMean))"
    }

    /// How the week sits against the weeks before it, in the same words the
    /// server's briefing uses, so the card and the coach's sentence can never
    /// disagree about the same number.
    ///
    /// Nil when the series was too thin for a trend — which is absence rather
    /// than stability, and must not be drawn as "no change". Zero *is* a
    /// measured answer and says so.
    public func trendPhrase(in unit: HealthUnit) -> String? {
        guard let trend = trendFromBaseline else { return nil }
        guard trend != 0 else { return "in line with your recent baseline" }

        let size = abs(trend)
        return "\(size) \(unit.after(size)) \(trend > 0 ? "above" : "below") your recent baseline"
    }
}

/// A metric's unit as prose reads it after a number, in both forms.
///
/// The breathing rate is the reason this is not a `String`: a trend of one is
/// "1 breath a minute below your recent baseline", and the plural form there is
/// the sort of wrong that makes the whole card read as machine output. `bpm`
/// and `ms` do not inflect and say so through [`HealthUnit/flat(_:)`].
///
/// The mirror of the server's own `Unit` in `assistant::prompt`, and deliberately
/// so: the card and the coach's sentence describe the same number, and a unit
/// that inflected on one side only would be the two of them disagreeing about
/// it in the one place a person could see both.
public struct HealthUnit: Sendable, Equatable {
    private let one: String
    private let many: String

    public init(one: String, many: String) {
        self.one = one
        self.many = many
    }

    /// A unit that reads the same however many there are.
    public static func flat(_ unit: String) -> Self {
        Self(one: unit, many: unit)
    }

    /// The form that follows `value`. Callers pass a magnitude, never a signed
    /// trend — a negative takes the plural, which is right for a delta of -2
    /// and never reached for -1.
    public func after(_ value: Int) -> String {
        value == 1 ? one : many
    }
}

/// Folds a daily series — typically the last eight weeks of one metric — into
/// the coarse summary the coach is allowed to see.
///
/// Pure on purpose: everything load-bearing about health data happens here, in
/// a function of values, so every threshold below is host-testable without a
/// Health store. The seam (`HealthStore`) only fetches.
///
/// The minimum-evidence thresholds exist because an under-evidenced trend is
/// worse than none: "your resting heart rate is up" computed from four
/// scattered readings would send the coach chasing noise, and a person trusts
/// exactly one such wrong sentence. Below threshold the answer is absence —
/// a nil trend, or no snapshot at all — never a zero, because zero is a
/// reading and absence is not.
public enum HealthSummaryBuilder {
    /// Days of history a trend needs before it is worth stating.
    public static let minimumTrendDays = 10

    /// The shortest stretch, first day to last, a trend may be drawn across.
    /// Ten readings inside a fortnight say nothing about a baseline.
    public static let minimumTrendSpanDays = 21

    /// How many days back from `now` count as "recent" — the window the mean
    /// summarises and the trend compares against everything older.
    public static let recentDays = 7

    /// A calendar-free day. Coarse arithmetic is the point: an hour of daylight
    /// saving cannot move a whole-unit weekly mean, and a fixed day keeps this
    /// a pure function of its arguments rather than of a time zone.
    private static let day: TimeInterval = 86400

    /// The summary `series` supports, or nil when the recent window is empty.
    ///
    /// `series` is a daily series — at most one entry per day, as the
    /// `HealthStore` queries answer. Entries dated after `now` are ignored:
    /// a device clock that has been forward and back again is not evidence.
    public static func snapshot(of series: [DailyQuantity], asOf now: Date) -> HealthSnapshot? {
        let usable = series.filter { $0.day <= now }
        let cutoff = now.addingTimeInterval(-TimeInterval(recentDays) * day)

        let recent = usable.filter { $0.day > cutoff }
        guard !recent.isEmpty else { return nil }
        let recentMean = mean(of: recent)
        guard let sevenDayMean = roundedInteger(recentMean) else { return nil }

        return HealthSnapshot(
            sevenDayMean: sevenDayMean,
            trendFromBaseline: trend(of: usable, olderThan: cutoff, against: recentMean)
        )
    }

    /// The rounded delta of the recent mean against everything before the
    /// window, or nil when the series is too thin to clear the thresholds.
    private static func trend(
        of usable: [DailyQuantity],
        olderThan cutoff: Date,
        against recentMean: Double
    ) -> Int? {
        let baseline = usable.filter { $0.day <= cutoff }
        let days = usable.map(\.day)
        guard
            !baseline.isEmpty,
            usable.count >= minimumTrendDays,
            let first = days.min(),
            let last = days.max(),
            last.timeIntervalSince(first) >= TimeInterval(minimumTrendSpanDays) * day
        else {
            return nil
        }

        return roundedInteger(recentMean - mean(of: baseline))
    }

    /// The arithmetic mean of a non-empty series' values.
    private static func mean(of series: [DailyQuantity]) -> Double {
        series.reduce(0) { $0 + $1.value } / Double(series.count)
    }

    /// A rounded integer only where the arithmetic stayed finite and fits.
    ///
    /// `DailyQuantity` rejects non-finite inputs, but a sum can still overflow
    /// while averaging otherwise finite values. Keeping the conversion failable
    /// makes that metric absent rather than asking `Int.init` to trap.
    private static func roundedInteger(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded()
        guard rounded >= Double(Int.min), rounded < Double(Int.max) else { return nil }
        return Int(rounded)
    }
}
