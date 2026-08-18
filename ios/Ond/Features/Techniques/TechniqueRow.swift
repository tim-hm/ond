import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One exercise in the list: what it is called, what it is for, and — drawn to
/// scale on the right — the shape of one cycle of it.
///
/// The bars sit beside the words rather than under them because they are the
/// same fact stated twice: the caption's "8 cycles · 16s each" is the sentence,
/// and the bars are the picture, so a reader takes whichever they read faster.
/// They go entirely at accessibility sizes, where the words need the width and a
/// 56-point figure would take a third of it to say nothing new.
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
        .padding(.vertical, Theme.Spacing.close)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(spacing: Theme.Spacing.close) {
                Text(technique.name)
                    .font(.headline)

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

            // Curated or written by the person reading it, both arrive here.
            // Empty where an author said nothing, and an empty `Text` is a
            // blank line rather than nothing.
            if !technique.summary.isEmpty {
                Text(technique.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Ink.secondary)
            }

            HStack(spacing: Theme.Spacing.close) {
                technique.rowCaption
                    .font(.caption)

                // Only where there is one. An exercise somebody wrote carries no
                // grade and gets no chip, which is the whole of what this app
                // has to say about the research on a pattern typed this morning.
                if let grade = technique.evidenceGrade {
                    EvidenceChip(grade: grade)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Technique {
    /// "relax · 8 cycles · 16s each". What the exercise is for, then the shape of
    /// it — the two things somebody choosing between nine of them is comparing.
    ///
    /// The goal leads because it is what the section header above this row used to
    /// say, and one word is all it ever needed: five headers' worth of type, folded
    /// into the line each row was already carrying.
    ///
    /// That word alone carries `goal.accent`; the facts after it stay in tertiary
    /// ink. The row used to stroke a figure at its far end in the same accent, but
    /// at row size the drawing was texture rather than information, so the word is
    /// now the accent's only carrier. Colouring the whole caption would spend it
    /// on cycle counts that mean nothing by it, and cost contrast on the half
    /// nobody needs colour for.
    ///
    /// Legible only because these rows are transparent over `paletteGround()`:
    /// `ThemeColorTests` measures the goal accents as small text on that ground,
    /// and they do not all clear AA on `Surface/Raised`. Put a card behind this row
    /// and the colour comes back out — `GoalBadge` is the treatment that survives
    /// a card.
    var rowCaption: Text {
        Text(
            "\(Text(goal.intentObject).foregroundStyle(goal.accent)) · \(Text(shapeDescription).foregroundStyle(Theme.Ink.tertiary))"
        )
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
