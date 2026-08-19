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
                RhythmBars(stage: stage, goal: technique.goal)
            }
        }
        .padding(.vertical, Theme.Spacing.standard)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(spacing: Theme.Spacing.close) {
                Text(technique.name)
                    .font(.headline)
                    // The spec tracks row titles −1%; of 17pt.
                    .tracking(-0.17)
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
    /// "2 in · 1 in · 7 out · 5 min": the rhythm once, then the length. It
    /// says the shape without repeating the catalogue's prose or asking the
    /// tiny figure to carry exact values.
    var listDetail: String {
        "\(rhythm(joinedBy: " · ")) · \(plannedDuration.glanceable)"
    }
}
