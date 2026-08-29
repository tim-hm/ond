import OndKit
import OndUI
import SwiftUI

/// How well evidenced an exercise is, in the one word a row has space for.
///
/// The evidence section is the honest half of what this app says about a
/// breath, and until now it only reached somebody who had already chosen the
/// exercise and opened its screen. The chip puts the same judgement where the
/// choosing happens.
///
/// **Both grades are drawn the same.** A green chip and an amber one would make
/// the scale a recommendation — better and worse exercises — when what it grades
/// is how much has been trialled, not how well anything works. The word is the
/// whole of it; the colour says only "this is a mark, not a sentence".
///
/// At `ios/Ond/` on `GoalBadge`'s reasoning: Home, Protocols and the Evidence
/// heading on an exercise's own screen draw one, and none of them owns it. It
/// cannot go on to `OndUI`, which knows nothing about an evidence grade and must
/// not learn.
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
