import OndKit
import OndUI
import SwiftUI

/// What your heart was doing around the last few sessions. There is no target
/// and no direction that counts as progress — ten readings over four weeks
/// cannot separate sleep, caffeine, illness or the hour — so the card states
/// what was measured and refuses to interpret it. Nothing is stored:
/// `HealthContextModel` reads Health per draw, and this draws what it hands over.
struct PracticeHeartCard: View {
    let heartline: PracticeHeartline

    /// How tall a bar stands at its fullest.
    private static let plotHeight: CGFloat = 28

    /// What a practice with no reading stands at, and the floor under one with a
    /// reading. `PracticeChartView`'s stub taken at this plot's scale rather
    /// than its value — four points of twenty-eight is what three of
    /// seventy-six is over there — for its reason: an absence has to be a mark
    /// somebody can see rather than a gap read as the end of the data.
    private static let stub: CGFloat = 4

    /// Between bars. Wider than the four-week chart's two points because ten
    /// bars share the width twenty-eight do, so there is room to separate them.
    private static let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Around your practice")
                .eyebrow()

            Text("Heart rate")
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            plot

            Text(Self.caption)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(Theme.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("practice-heart-card")
    }

    /// The bars, spoken as one thing rather than ten — `PracticeChartView`
    /// settled the same question the same way. The spoken value carries the
    /// numbers the bars encode; a caption alone would leave a VoiceOver reader
    /// with the disclaimer and none of the data.
    private var plot: some View {
        // Read once rather than per bar, on `PracticeChartView`'s reasoning:
        // `fraction(of:)` re-derives the range from every mark it holds, and
        // this is a hand-drawn plot rather than a scale a framework asks for.
        let scale = heartline.range

        return HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(heartline.marks) { mark in
                bar(for: mark, under: scale)
            }
        }
        .frame(height: Self.plotHeight, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate around your practice")
        .accessibilityValue(spokenValue)
    }

    /// One practice. Full-strength ink where the refresh spec asks for 35%
    /// (55% today): those measure 1.54:1–2.15:1 against a 3:1 floor for a
    /// non-text mark; full `Breath.inhale` clears 4.06:1 light, 7.86:1 dark —
    /// the same deviation `PracticeChartView` records. Opacity cannot mark
    /// today (0.85 is the lowest alpha clearing 3:1), so today takes an `Ink.primary` cap.
    @ViewBuilder
    private func bar(
        for mark: PracticeHeartline.Mark,
        under scale: ClosedRange<Int>?
    ) -> some View {
        let fraction = mark.beatsPerMinute.flatMap { rate in
            scale.map { PracticeHeartline.fraction(of: rate, in: $0) }
        }

        VStack(spacing: 1) {
            if mark.isToday, fraction != nil {
                Capsule()
                    .fill(Theme.Ink.primary)
                    .frame(height: 1.5)
            }

            RoundedRectangle(cornerRadius: Theme.Radius.mark)
                .fill(fraction == nil ? Theme.Surface.line : Theme.Breath.inhale)
                .frame(height: height(of: fraction))
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func height(of fraction: Double?) -> CGFloat {
        guard let fraction else { return Self.stub }
        return Self.stub + (Self.plotHeight - Self.stub) * fraction
    }

    /// Why the card is showing no trend.
    private static let caption =
        "There are too few readings to show a trend."

    /// What the bars say, for somebody who cannot see them.
    private var spokenValue: String {
        let counted = "\(heartline.readingCount) of your last \(heartline.marks.count) "
            + "practices have a reading"

        guard let range = heartline.range else { return counted }
        return "\(counted), from \(range.lowerBound) to \(range.upperBound) beats a minute. "
            + Self.caption
    }
}
