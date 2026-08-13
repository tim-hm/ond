import Charts
import OndKit
import OndUI
import SwiftUI

/// The last four weeks, one bar a day.
///
/// The one thing on Home the tiles cannot say: not how many days, but *which* —
/// whether the practice is a run, a weekend habit, or a fortnight ago. That is a
/// shape rather than a number, so it is the one place a drawing earns its room.
///
/// **One hue, not five.** The obvious version of this chart stacks each day by
/// what the sessions were for and colours the segments with `goal.accent`, and
/// it was built that way first. Measured as adjacent fills rather than as
/// badges, those five accents separate by as little as ΔE 7.1 in the light
/// appearance and 7.6 in the dark one, against a floor of 15 for a reader with
/// full colour vision — they walk one arc of the wheel on purpose, which is what
/// makes them read as one palette everywhere a *word* is carrying the identity
/// beside them. A stack has no word. So the bars carry magnitude in the brand
/// accent, one series and therefore no legend, and the goal is stated in the
/// caption underneath, where it is legible to everybody.
///
/// Hidden entirely below `isWorthCharting`. A single bar in an empty frame says
/// less than the sentence above it and takes six times the room.
struct PracticeChartView: View {
    let rhythm: PracticeRhythm

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Last four weeks")
                .font(.headline)

            chart

            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private var chart: some View {
        Chart(rhythm.days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Sessions", day.total)
            )
            .foregroundStyle(Theme.Accent.brand)
            .cornerRadius(Theme.Radius.mark)
            .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue("\(day.total)")
        }
        // The ceiling is the busiest day rather than the automatic scale, which
        // rounds up to a number nobody practised — a chart whose tallest bar
        // reaches two thirds of the frame reads as a target half met.
        .chartYScale(domain: 0 ... rhythm.busiestDay)
        .chartYAxis {
            // The floor and the ceiling, and nothing between. The automatic
            // scale puts halves on a count, and there is no such thing as half
            // a session; a rule per whole number is a grid rather than an axis
            // once somebody has a busy fortnight.
            AxisMarks(values: [0, rhythm.busiestDay]) {
                AxisGridLine().foregroundStyle(Theme.Surface.line)
                AxisValueLabel().foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .chartXAxis {
            // A mark a week, so four labels sit under twenty-eight bars rather
            // than a row of type nobody can read.
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .frame(height: Self.height)
    }

    /// Tall enough for a bar to have a shape, short enough that the chart does
    /// not become the screen. The stats above it are still the headline.
    private static let height: CGFloat = 120

    /// How many of the four weeks carried practice, and what most of it was for.
    ///
    /// The goal in words, which is the whole reason the fold splits by one — see
    /// the note above about the accents. Silent about the goal where the window
    /// somehow carries none, rather than printing a dangling sentence.
    private var caption: String {
        let days = "\(rhythm.daysPractised) of the last \(PracticeRhythm.window) days"

        guard let goal = rhythm.leadingGoal else { return days }
        return "\(days) · mostly \(goal.title.lowercased())"
    }
}
