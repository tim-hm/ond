import OndKit
import OndUI
import SwiftUI

/// The chart's three four-week totals: sessions, minutes, and days practised.
/// Days is the one the evidence is about — the trial's outcomes scaled with
/// how many days people practised, not how long a sitting ran. Deliberately
/// not the streak: a number that resets to zero for missing one day is a
/// punishment dressed as a total, and beside these it would lead.
struct PracticeFigures: View {
    let rhythm: PracticeRhythm

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
            figure(rhythm.sessions, "sessions")
            figure(rhythm.minutes, "minutes")
            figure(rhythm.daysPractised, "days practised")
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
