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

    /// The same colour where it carries words rather than a fill — the
    /// qualifier line under the orb is the one place a session sets small type
    /// in its own colour. Split from ``accent`` because `Accent.night` is too
    /// deep to read at that size.
    @MainActor
    var textAccent: Color {
        timeline.register.textAccent(over: technique.goal)
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

    /// The same choice where the colour carries words. The playful register
    /// answers with its own fill colour: `Accent.play` reads at 5.49:1 on the
    /// light ground and 8.27:1 on the dark one, so it needs no lifted twin the
    /// way `sleep` does. `ThemeColorTests` measures it.
    func textAccent(over goal: TechniqueGoal) -> Color {
        switch self {
        case .plain: goal.textAccent
        case .playful: accent(over: goal)
        }
    }
}

public extension DialStop {
    /// The colour this stop is drawn in: the register's where a route asked for
    /// one, the exercise's goal otherwise. Only a Moment carries a register, so
    /// this is the one place in the app where a route colours a card rather than
    /// the exercise behind it — and why `play` is its own token, not an alias of
    /// `spark`.
    var accent: Color {
        register.accent(over: goal)
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
