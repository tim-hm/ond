import OndKit
import OndUI
import SwiftUI

struct PracticeHeartCard: View {
    let heartline: PracticeHeartline

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Around your practice").eyebrow()
            Text("Heart rate")
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            if let range = heartline.range {
                Text("\(range.lowerBound)–\(range.upperBound) bpm")
                    .font(.title2).monospacedDigit()
                Text("Range of practice averages")
                    .font(.caption).foregroundStyle(Theme.Ink.secondary)
            }

            Text(
                "Readings for \(heartline.readingCount) of your last \(heartline.marks.count) practices."
            )
            .font(.caption)

            DisclosureGroup("View readings") {
                VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                    ForEach(heartline.marks.reversed()) { mark in
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Text(mark.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Theme.Ink.secondary)
                            Text(mark.beatsPerMinute.map { "\($0) bpm average" } ?? "No reading")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.close)
            }

            Text(
                "Averages cover each practice and the three minutes after it. These readings do not measure how well you breathed."
            )
            .font(.caption)
            .foregroundStyle(Theme.Ink.secondary)
        }
        .padding(Theme.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("practice-heart-card")
    }
}
