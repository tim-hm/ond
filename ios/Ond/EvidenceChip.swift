import OndKit
import OndUI
import SwiftUI

/// How much research an exercise has behind it, in plain language. Both
/// readings are drawn the same: a green chip and an amber one would make the
/// words a recommendation, when they say how much has been trialled, not how
/// well anything works. At `ios/Ond/` because three surfaces draw it and none
/// owns it; `OndUI` knows nothing about an evidence grade and must not.
struct EvidenceChip: View {
    let grade: EvidenceGrade
    var color = Theme.Ink.tertiary

    var body: some View {
        Text(grade.title)
            .eyebrow(color)
            .padding(.horizontal, Theme.Spacing.close)
            .padding(.vertical, Theme.Spacing.tight)
            .overlay(
                Capsule().strokeBorder(Theme.Surface.line, lineWidth: 0.5)
            )
    }
}
