import Charts
import OndKit
import OndUI
import SwiftUI

struct PracticeChartView: View {
    let rhythm: PracticeRhythm
    let hasPractised: Bool
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Last four weeks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Chart(rhythm.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", Double(day.durationMilliseconds) / 60000)
                )
                .foregroundStyle(Theme.Breath.inhale)
                if let selectedDay, selectedDay.id == day.id {
                    RuleMark(x: .value("Selected day", day.date, unit: .day))
                        .foregroundStyle(Theme.Ink.primary)
                }
            }
            .chartYScale(domain: 0 ... ceiling)
            .chartYAxisLabel("Minutes")
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    AxisTick()
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily practice minutes, last four weeks")
            .accessibilityValue(selectedDescription ?? summary)
            .accessibilityHint("Swipe up or down to inspect a day")
            .accessibilityAdjustableAction { direction in
                let current = selectedDay
                    .flatMap { day in rhythm.days.firstIndex { $0.id == day.id } }
                guard let current else {
                    selectedDate = rhythm.days.last?.date
                    return
                }
                let next = direction == .increment ? current + 1 : current - 1
                guard rhythm.days.indices.contains(next) else { return }
                selectedDate = rhythm.days[next].date
            }

            Text(selectedDescription ??
                (hasPractised ? "Touch the chart to inspect a day." : summary))
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .frame(minHeight: 36, alignment: .topLeading)

            if hasPractised {
                Text(summary).font(.caption).foregroundStyle(Theme.Ink.secondary)
            }
        }
        .accessibilityIdentifier("practice-chart")
    }

    private var ceiling: Double {
        let minutes = Double(rhythm.busiestDayDurationMilliseconds) / 60000
        return max(5, (minutes / 5).rounded(.up) * 5)
    }

    private var selectedDay: PracticeRhythm.Day? {
        guard let selectedDate else { return nil }
        return rhythm.days.first { Calendar.autoupdatingCurrent.isDate(
            $0.date,
            inSameDayAs: selectedDate
        ) }
    }

    private var selectedDescription: String? {
        guard let day = selectedDay else { return nil }
        let minutes = Double(day.durationMilliseconds) / 60000
        return "\(day.date.formatted(.dateTime.weekday().day().month())): "
            + "\(minutes.formatted(.number.precision(.fractionLength(0 ... 1)))) min, "
            + "\(day.sessions) \(day.sessions == 1 ? "practice" : "practices")"
    }

    private var summary: String {
        guard hasPractised else { return "Your practice minutes will appear here." }
        return "\(rhythm.daysPractised) of the last \(PracticeRhythm.window) days"
    }
}
