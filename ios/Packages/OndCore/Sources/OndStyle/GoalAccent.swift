import OndKit
import OndUI
import SwiftUI

public extension SessionModel {
    /// The colour this session is drawn in, wherever it is drawn. Stated once:
    /// each screen deriving the register–goal pairing again is how the Live
    /// Activity painted a playful breath blue while the app painted it rose.
    /// Surfaces holding a `SessionPresence` reach ``CopyRegister/accent(over:)``
    /// directly — they have the two halves and no model.
    @MainActor
    var accent: Color {
        timeline.register.accent(over: technique.goal)
    }
}

public extension CopyRegister {
    /// The colour a session in this register is grounded in. The register wins
    /// where it has one: the children's exercise is seeded `calm` and would
    /// otherwise wear box breathing's sea blue. Takes the goal rather than
    /// reading it, so the fallback ordering is stated at the one call site
    /// that has both.
    func accent(over goal: TechniqueGoal) -> Color {
        switch self {
        case .plain: goal.accent
        case .playful: Theme.Accent.play
        }
    }
}

public extension TechniqueGoal {
    /// The palette entry a goal is drawn in.
    ///
    /// One mapping, read by both apps, because a second copy of it fails
    /// silently: the same technique comes out a different colour on the wrist
    /// than in the hand, and nothing but a person's memory catches it.
    var accent: Color {
        switch self {
        case .calm: Theme.Accent.settle
        case .sleep: Theme.Accent.night
        case .energy: Theme.Accent.spark
        case .reset: Theme.Accent.restore
        case .focus: Theme.Accent.attend
        }
    }

    /// The goal's colour when it is set as text on a dark surround rather than
    /// poured as a fill. Only `sleep` splits the two: `Accent.night` sits too
    /// deep to read as small text, so it takes the lifted `Accent.nightText`.
    /// Every other goal reads at AA in its own accent.
    var textAccent: Color {
        switch self {
        case .sleep: Theme.Accent.nightText
        default: accent
        }
    }
}
