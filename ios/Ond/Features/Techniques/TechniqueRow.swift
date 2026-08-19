import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One exercise in the list: what it is called, its compact rhythm, and — drawn
/// to scale on the right — the shape of one cycle of it.
///
/// The catalogue's explanatory paragraph belongs on the exercise's own screen;
/// eleven of them here turn a choice into an article. The rhythm sentence and
/// bars are the same fact in two forms, so the bars go at accessibility sizes
/// where the sentence needs their width.
struct TechniqueRow: View {
    let technique: Technique
    var isLocked = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            words

            if !dynamicTypeSize.isAccessibilitySize, let stage = RhythmBars.cycle(of: technique) {
                Spacer(minLength: Theme.Spacing.close)
                RhythmBars(stage: stage)
            }
        }
        .padding(.vertical, Theme.Spacing.standard)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(spacing: Theme.Spacing.close) {
                Text(technique.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        // The brand accent rather than a warning colour: the
                        // lock is the app offering something, not the app
                        // telling somebody off.
                        .foregroundStyle(Theme.Accent.brand)
                        .accessibilityLabel("Included with önd+")
                }
            }

            Text(technique.listDetail)
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Technique {
    /// "2 in · 1 in · 7 out · 5 min" for a cycle, or the compact stage summary
    /// for a protocol. It says the rhythm once without repeating the catalogue's
    /// prose or asking the tiny figure to carry exact values.
    var listDetail: String {
        guard !isStaged, let stage = stages.first else {
            return "\(shapeDescription) · \(plannedDuration.glanceable)"
        }

        let phases = stage.phases.map { phase in
            "\(phase.duration.inSeconds) \(phase.kind.shortInstruction.lowercased())"
        }
        return (phases + [plannedDuration.glanceable]).joined(separator: " · ")
    }

    /// "8 cycles · 16s each", or "3 rounds · you end the holds". The shape of
    /// the technique at a glance — and the staged ones are a different
    /// proposition from the cyclic ones, so they say so.
    var shapeDescription: String {
        guard !isStaged, let stage = stages.first else {
            let unit = recommendedRounds == 1 ? "round" : "rounds"
            return hasOpenEndedStage
                ? "\(recommendedRounds) \(unit) · you end the holds"
                : "\(recommendedRounds) \(unit) · \(stages.count) stages"
        }

        let seconds = stage.cycleDuration.components.seconds
        return "\(stage.cycles) cycles · \(seconds)s each"
    }
}
