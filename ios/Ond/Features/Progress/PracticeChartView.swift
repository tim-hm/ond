import Charts
import OndKit
import OndUI
import SwiftUI

/// The last four weeks, one bar a day.
///
/// Home's summary says how many days; this says which ones, revealing whether
/// the practice is a run, a weekend habit, or a fortnight ago. That is a shape
/// rather than a number, so the detailed Progress screen is where it earns its
/// room.
///
/// **One hue, not five.** The five goal accents separate by as little as Delta E
/// 7.1 in the light appearance and 7.6 in the dark one, against a floor of 15
/// for a reader with full colour vision. They work where a word names the goal,
/// but not as adjacent unlabelled fills. The bars therefore carry magnitude in
/// the brand accent and state the leading goal in the caption.
///
/// Before `isWorthCharting`, the section keeps its place but replaces the empty
/// frame with one sentence. A single bar says less than that sentence while
/// taking six times the room, but hiding the section altogether makes Progress
/// look as though it has no chart.
struct PracticeChartView: View {
    let rhythm: PracticeRhythm

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Last four weeks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if rhythm.isWorthCharting {
                chart

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            } else {
                Text(emptyDetail)
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)
            }
        }
        .accessibilityIdentifier("practice-chart")
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
        // The busiest day is the ceiling. An automatic scale can round above it
        // and make the strongest practice day look like a target partly met.
        .chartYScale(domain: 0 ... rhythm.busiestDay)
        .chartYAxis {
            AxisMarks(values: [0, rhythm.busiestDay]) {
                AxisGridLine().foregroundStyle(Theme.Surface.line)
                AxisValueLabel().foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .frame(height: Self.height)
    }

    /// Tall enough for a bar to have a shape without becoming the screen.
    private static let height: CGFloat = 120

    /// How many of the four weeks carried practice, and what most of it was for.
    private var caption: String {
        let days = "\(rhythm.daysPractised) of the last \(PracticeRhythm.window) days"

        guard let goal = rhythm.leadingGoal else { return days }
        return "\(days) · mostly \(goal.title.lowercased())"
    }

    /// The threshold stated as progress, without drawing a chart whose only
    /// information is that this person has started.
    private var emptyDetail: String {
        if rhythm.daysPractised == 1 {
            "Your first practice day is recorded. A four-week rhythm appears after a second."
        } else {
            "Your four-week rhythm will appear after sessions on two different days."
        }
    }
}
