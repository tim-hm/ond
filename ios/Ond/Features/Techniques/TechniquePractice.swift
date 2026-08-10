import OndKit
import OndUI
import SwiftUI

/// How you do it, under the picture of it.
///
/// Below the figure rather than above, because it is a caption on a drawing
/// rather than an introduction to one: the summary's shape of the thing, the
/// passage the figure marks only with a letter, and the dose. Above the figure,
/// the same words read as something to get through before the picture.
///
/// The dialled technique — the counts here are the ones the dials under Customise
/// are set to, and a screen stating a curated dose above somebody's own numbers
/// would be lying in the calmest possible voice.
struct TechniquePractice: View {
    let technique: Technique

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if let summary = technique.practiceSummary {
                Text(summary)
            }

            if let passage = technique.passageNote {
                Text(passage)
            }

            Text(technique.doseDescription)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Ink.secondary)
    }
}
