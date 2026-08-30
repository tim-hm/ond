import OndKit
import OndUI
import SwiftUI

/// The last four weeks, one bar a day — which days, not how many. One hue,
/// not five: the goal accents separate by as little as Delta E 7.1 against a
/// floor of 15, so they fail as adjacent unlabelled fills. A missed day is
/// drawn as a hairline stub, never skipped — a gap reads as the end of the
/// data, and the stubs alone are what an untouched install draws.
struct PracticeChartView: View {
    let rhythm: PracticeRhythm

    /// Whether this device holds any session at all. A lifetime fact, not the
    /// window's: somebody who stopped a month ago has practised, and must not
    /// be told their first session is still ahead of them.
    let hasPractised: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last four weeks")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("minutes a day")
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }

            plot

            Text(summary)
                .font(hasPractised ? .caption : .subheadline)
                .foregroundStyle(hasPractised ? Theme.Ink.tertiary : Theme.Ink.secondary)
        }
        .accessibilityIdentifier("practice-chart")
    }

    /// The bars, spoken as one thing rather than twenty-eight. The audit is
    /// right to refuse per-bar elements: an eleven-point mark is not something
    /// anybody can land on, and four weeks of "Tue 14 April, 0" is a worse
    /// listen than the sentence under it. The caption *is* the spoken chart.
    private var plot: some View {
        // Read once rather than per bar: the ceiling folds a 28-element array on
        // every read, and this is a hand-drawn plot rather than a scale the
        // framework asks for twice.
        let ceiling = rhythm.busiestDayDurationMilliseconds

        return HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(rhythm.days) { day in
                bar(for: day, under: ceiling)
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last four weeks")
        .accessibilityValue(summary)
    }

    private func bar(for day: PracticeRhythm.Day, under ceiling: Int) -> some View {
        // Full strength rather than the refresh spec's 30% wash: at 30% the bar
        // measures 1.44:1 against the light ground and 1.71:1 against the dark
        // one, where a mark carrying the whole of a chart's information owes
        // 3:1. This is the same ink the chart has always drawn — inhale is the
        // brand accent — and it clears at 4.06:1 and 7.86:1.
        RoundedRectangle(cornerRadius: Theme.Radius.mark)
            .fill(day.sessions > 0 ? Theme.Breath.inhale : Theme.Surface.line)
            .frame(height: height(of: day, under: ceiling))
            .frame(maxWidth: .infinity)
    }

    /// How tall this day's bar stands. The busiest day is the ceiling — an
    /// automatic scale can round above it and make the strongest practice day
    /// look like a target partly met.
    private func height(of day: PracticeRhythm.Day, under ceiling: Int) -> CGFloat {
        guard day.sessions > 0 else { return Self.stub }
        return max(
            Self.stub,
            Self.height * CGFloat(day.durationMilliseconds) / CGFloat(ceiling)
        )
    }

    /// Tall enough for a bar to have a shape without becoming the screen.
    private static let height: CGFloat = 76

    /// What a day with nothing in it stands at, and the floor under a day with
    /// something: a single session in a busy fortnight still has to be a mark
    /// somebody can see beside the day that had four.
    private static let stub: CGFloat = 3

    /// Between bars. Narrow, because twenty-eight of these share a phone's
    /// width and the bar is what should get it.
    private static let gap: CGFloat = 2

    /// What the bars say, printed under them and spoken as their value.
    private var summary: String {
        hasPractised ? caption : "This chart fills in once you have practised."
    }

    /// How many of the four weeks carried practice, and what most of it was for.
    private var caption: String {
        let days = "\(rhythm.daysPractised) of the last \(PracticeRhythm.window) days"

        guard let goal = rhythm.leadingGoal else { return days }
        return "\(days) · mostly \(goal.title.lowercased())"
    }
}
