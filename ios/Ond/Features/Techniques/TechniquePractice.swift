import OndKit
import OndUI
import SwiftUI

/// How you do it, under the picture of it: the phases as lines, then the
/// dose. The steps say what the figure cannot — which passage the air takes,
/// and that a retention ends when the person does. Drawn from the dialled
/// technique, so the counts match the Customise dials; a curated dose above
/// somebody's own numbers would lie. The summary is `Technique.closingNote`'s.
struct TechniquePractice: View {
    let technique: Technique

    var body: some View {
        // Every line in the block is a subheadline and every one but the
        // instruction is secondary, so both are set once here and overridden
        // where a line differs.
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            ForEach(Array(technique.stages.enumerated()), id: \.offset) { index, stage in
                steps(of: stage, at: index)
            }

            Text(technique.doseDescription)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Ink.secondary)
    }

    /// One stage's lines, titled where there is more than one stage to tell
    /// apart. The title is `Stage.title(at:)`, shared with the figures above,
    /// so a stage is not called two things a hundred points apart.
    private func steps(of stage: Stage, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if technique.isStaged {
                Text(stage.title(at: index))
                    .fontWeight(.semibold)
            }

            ForEach(stage.steps) { step in
                row(step)
            }
        }
    }

    /// What to do on the leading edge, how long for on the trailing one, so a
    /// stage's counts line up as a column and the rhythm is read off them at a
    /// glance rather than assembled from four sentences.
    private func row(_ step: BreathStep) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(step.instruction)
                .foregroundStyle(Theme.Ink.primary)

            Spacer(minLength: Theme.Spacing.standard)

            Text(step.count)
                .monospacedDigit()
        }
    }
}
