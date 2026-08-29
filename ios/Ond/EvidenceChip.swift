import OndKit
import OndUI
import SwiftUI

/// How well evidenced an exercise is, in the one word a row has space for.
/// Both grades are drawn the same: a green chip and an amber one would make
/// the scale a recommendation, when it grades how much has been trialled, not
/// how well anything works. At `ios/Ond/` because three surfaces draw it and
/// none owns it; `OndUI` knows nothing about an evidence grade and must not.
struct EvidenceChip: View {
    let grade: EvidenceGrade
    var color = Theme.Ink.tertiary
    /// Whether the visible chip says "Evidence: moderate" rather than the compact
    /// "Moderate" used where the surrounding section already names evidence.
    var includesSubject = false

    var body: some View {
        Text(includesSubject ? "Evidence: \(grade.title)" : grade.title)
            .eyebrow(color)
            .padding(.horizontal, Theme.Spacing.close)
            .padding(.vertical, Theme.Spacing.tight)
            .overlay(
                Capsule().strokeBorder(Theme.Surface.line, lineWidth: 0.5)
            )
            // Read as one phrase rather than as a bare adjective: "Limited"
            // alone, spoken after an exercise's name, sounds like a judgement on
            // the exercise instead of on the research about it.
            .accessibilityLabel("\(grade.title) evidence")
    }
}
