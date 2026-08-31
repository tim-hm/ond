import Foundation
@testable import OndKit
import Testing

/// The evidence thresholds are the product decision under test: the coach sees
/// a trend only when the series can support one, and below that it sees
/// absence — never a zero, never a guess.
@Suite("Health summary thresholds")
struct HealthSummaryBuilderTests {
    /// A moment with no significance beyond being fixed, so that "today" in a
    /// test is a value rather than whenever the suite happens to run.
    private static let now = Date(timeIntervalSince1970: 1_777_000_000)

    /// Valid readings from `(days ago, value)` pairs.
    private func readings(_ entries: [(Int, Double)]) -> [DailyQuantity] {
        entries.compactMap { daysAgo, value in
            DailyQuantity(
                day: Self.now.addingTimeInterval(-Double(daysAgo) * 86400),
                value: value
            )
        }
    }

    /// Seven recent days of one steady value — enough for a mean on its own,
    /// and the block every trend test builds on.
    private func steadyWeek(of value: Double) -> [DailyQuantity] {
        readings((0 ... 6).map { ($0, value) })
    }

    @Test("An empty series is no snapshot at all")
    func emptySeries() {
        #expect(HealthSummaryBuilder.snapshot(of: [], asOf: Self.now) == nil)
    }

    @Test("History with nothing recent is no snapshot at all")
    func staleSeries() {
        let series = readings((10 ... 30).map { ($0, 60) })
        #expect(HealthSummaryBuilder.snapshot(of: series, asOf: Self.now) == nil)
    }

    @Test("A few recent days make a mean but never a trend")
    func recentOnly() {
        let series = readings((0 ... 4).map { ($0, 61) })
        let snapshot = HealthSummaryBuilder.snapshot(of: series, asOf: Self.now)
        #expect(snapshot == HealthSnapshot(sevenDayMean: 61, trendFromBaseline: nil))
    }

    @Test("The trend is the recent mean against everything older")
    func trendMath() {
        let series = steadyWeek(of: 60)
            + readings([(14, 65), (21, 65), (28, 65)])
        let snapshot = HealthSummaryBuilder.snapshot(of: series, asOf: Self.now)
        #expect(snapshot == HealthSnapshot(sevenDayMean: 60, trendFromBaseline: -5))
    }

    @Test("Nine days of data withhold the trend; the tenth grants it")
    func minimumDaysEdge() {
        // Six recent, three old: nine days across a 24-day span — everything a
        // trend needs except the tenth day.
        let nine = readings((0 ... 5).map { ($0, 60) })
            + readings([(10, 65), (17, 65), (24, 65)])
        #expect(HealthSummaryBuilder.snapshot(of: nine, asOf: Self.now)?.trendFromBaseline == nil)

        let ten = nine + readings([(6, 60)])
        #expect(HealthSummaryBuilder.snapshot(of: ten, asOf: Self.now)?.trendFromBaseline == -5)
    }

    @Test("A 20-day span withholds the trend; 21 days grant it")
    func minimumSpanEdge() {
        let narrow = steadyWeek(of: 60)
            + readings([(14, 65), (17, 65), (20, 65)])
        #expect(HealthSummaryBuilder.snapshot(of: narrow, asOf: Self.now)?.trendFromBaseline == nil)

        let wide = steadyWeek(of: 60)
            + readings([(15, 65), (18, 65), (21, 65)])
        #expect(HealthSummaryBuilder.snapshot(of: wide, asOf: Self.now)?.trendFromBaseline == -5)
    }

    @Test("Means and trends round to whole units, halves away from zero")
    func rounding() {
        // Recent mean 62.5; baseline mean 65.0 → delta -2.5. Both halves must
        // move away from zero: 63 up, -3 down.
        let series = readings([(0, 62), (1, 63)])
            + readings((10 ... 21).map { ($0, 65) })
        let snapshot = HealthSummaryBuilder.snapshot(of: series, asOf: Self.now)
        #expect(snapshot == HealthSnapshot(sevenDayMean: 63, trendFromBaseline: -3))
    }

    @Test("Readings dated after now are not evidence")
    func futureReadings() {
        let tomorrow = readings([(-1, 200)])
        #expect(HealthSummaryBuilder.snapshot(of: tomorrow, asOf: Self.now) == nil)

        let snapshot = HealthSummaryBuilder.snapshot(
            of: steadyWeek(of: 60) + tomorrow,
            asOf: Self.now
        )
        #expect(snapshot?.sevenDayMean == 60)
    }

    @Test(
        "Non-finite daily quantities are refused",
        arguments: [Double.nan, .infinity, -.infinity]
    )
    func nonFiniteQuantitiesAreRefused(_ value: Double) {
        #expect(DailyQuantity(day: Self.now, value: value) == nil)
    }

    @Test("Invalid quantities are omitted while a finite metric remains")
    func invalidQuantitiesAreOmitted() {
        let quantities = [Double.nan, .infinity, -.infinity, 61].compactMap {
            DailyQuantity(day: Self.now, value: $0)
        }

        #expect(quantities.count == 1)
        #expect(
            HealthSummaryBuilder.snapshot(of: quantities, asOf: Self.now)
                == HealthSnapshot(sevenDayMean: 61, trendFromBaseline: nil)
        )
    }

    @Test("Overflowing finite arithmetic omits the metric instead of converting it")
    func overflowingMeanIsOmitted() {
        let quantities = readings([(0, Double.greatestFiniteMagnitude), (1, 1)])

        #expect(HealthSummaryBuilder.snapshot(of: quantities, asOf: Self.now) == nil)
    }

    /// The prose the card draws, in the same words the server's briefing uses.
    ///
    /// Zero is a measured answer and says so; a missing trend is absence and
    /// says nothing at all. Drawing "no change" for the second would claim a
    /// baseline comparison the evidence never supported.
    @Test("A trend reads as prose, and an absent one reads as nothing")
    func aTrendReadsAsProse() {
        let steady = HealthSnapshot(sevenDayMean: 62, trendFromBaseline: 0)
        #expect(steady.mean(in: .flat("bpm")) == "about 62 bpm")
        #expect(steady.trendPhrase(in: .flat("bpm")) == "in line with your recent baseline")

        let risen = HealthSnapshot(sevenDayMean: 66, trendFromBaseline: 4)
        #expect(risen.trendPhrase(in: .flat("bpm")) == "4 bpm above your recent baseline")

        let fallen = HealthSnapshot(sevenDayMean: 44, trendFromBaseline: -9)
        #expect(fallen.trendPhrase(in: .flat("ms")) == "9 ms below your recent baseline")

        let thin = HealthSnapshot(sevenDayMean: 62, trendFromBaseline: nil)
        #expect(thin.trendPhrase(in: .flat("bpm")) == nil)
        #expect(thin.mean(in: .flat("bpm")) == "about 62 bpm")
    }

    /// A unit that inflects does so in both halves of the sentence — and this
    /// is the whole reason the unit is a type rather than a string. "1 breaths
    /// a minute below your recent baseline" is the sort of wrong that makes the
    /// card read as machine output, and a delta of one is the commonest one a
    /// breathing rate ever shows.
    @Test("A breathing trend of one reads as one breath")
    func aBreathingTrendOfOneIsSingular() {
        let breaths = HealthUnit(one: "breath a minute", many: "breaths a minute")

        let single = HealthSnapshot(sevenDayMean: 13, trendFromBaseline: -1)
        #expect(single.trendPhrase(in: breaths) == "1 breath a minute below your recent baseline")
        #expect(single.mean(in: breaths) == "about 13 breaths a minute")

        let several = HealthSnapshot(sevenDayMean: 16, trendFromBaseline: 2)
        #expect(several.trendPhrase(in: breaths) == "2 breaths a minute above your recent baseline")
    }
}
