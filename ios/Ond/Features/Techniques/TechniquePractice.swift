import OndKit
import OndUI
import SwiftUI

/// How you do it, under the picture of it.
///
/// The phases as lines to follow, then the dose. Below the figure rather than
/// above, because it is a caption on a drawing rather than an introduction to
/// one — and first of the written blocks, because "what do I do" is the question
/// somebody opened this screen with. What the exercise has to say for itself is
/// below the coach door, for whoever is still reading by then.
///
/// No summary here: it is `Technique.closingNote`'s, and the reason is stated
/// there.
///
/// The steps say what the figure cannot. A drawing labels its runs `in · 4` and
/// leaves the rest to the reader: which passage the air takes, and that a
/// retention ends when the person does rather than when a number runs out.
///
/// The dialled technique — the counts here are the ones the dials under Customise
/// are set to, and a screen stating a curated dose above somebody's own numbers
/// would be lying in the calmest possible voice.
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

    /// One stage's lines, under its own title where there is more than one stage
    /// to tell apart.
    ///
    /// The title is `Stage.title(at:)`, which the figures above these use
    /// too — one spelling, so a stage is not called two things a hundred points
    /// apart on one screen.
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
