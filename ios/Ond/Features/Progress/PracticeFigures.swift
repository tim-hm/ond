import OndKit
import OndUI
import SwiftUI

/// The three totals, over the chart: sessions, minutes, and the days the
/// practice actually landed on.
///
/// Days practised is last and is the one the evidence is about — what people got
/// out of the month in the trial the daily exercise comes from scaled with how
/// many days they practised rather than with how long any one sitting ran.
/// `JourneyStats` says the same thing at greater length, and this is the screen
/// that shows it.
///
/// Deliberately not the streak. A run of consecutive days is a device for
/// keeping the days coming, and a number that resets to zero for missing one is
/// a punishment dressed as a total — the two beside each other would let the
/// wrong one lead.
struct PracticeFigures: View {
    let stats: JourneyStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // A row of three ordinarily; a column where the labels need the width.
        // Three 22-point numerals over three wrapped two-line labels is a grid
        // of fragments, and the figures are the one thing on this screen that
        // has to be readable at a glance.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.standard))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.standard))

        return layout {
            figure(stats.sessions, "sessions")
            figure(stats.minutes, "minutes")
            figure(stats.daysPractised, "days practised")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("\(value)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Ink.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
