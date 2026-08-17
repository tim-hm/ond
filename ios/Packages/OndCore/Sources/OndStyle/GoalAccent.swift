import OndKit
import OndUI
import SwiftUI

public extension SessionModel {
    /// The colour this session is drawn in, wherever it is drawn.
    ///
    /// The pairing of register and goal stated once, because every screen that
    /// shows a session needs it and each one deriving it again is how the Live
    /// Activity came to paint a playful breath in the goal's blue while the app
    /// beside it painted the same breath rose. The surfaces that hold a
    /// `SessionPresence` instead — the lock screen, the Island — reach
    /// ``CopyRegister/accent(over:)`` directly for the same reason, since they
    /// have the two halves and no model.
    @MainActor
    var accent: Color {
        timeline.register.accent(over: technique.goal)
    }
}

public extension CopyRegister {
    /// The colour a session in this register is grounded in.
    ///
    /// The register wins where it has one, which is the one place a route
    /// overrules the catalogue on more than wording: the children's exercise is
    /// seeded `calm` and would otherwise wear the same sea blue as box
    /// breathing, and a screen that says "smell the flower" in the adult palette
    /// is two registers at once.
    ///
    /// Takes the goal rather than reading it, so the fallback is stated at the
    /// one call site that has both and no surface has to remember the ordering.
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

    /// The goal's colour when it is set as text on a dark surround rather
    /// than poured as a fill.
    ///
    /// Only `sleep` splits the two: `Accent.night` sits deep enough to
    /// separate from `Breath.hold` inside one frame, which leaves it short as
    /// small text, so a suggestion card's eyebrow takes the lifted
    /// `Accent.nightText` instead. Every other goal reads at AA in its own
    /// accent.
    var textAccent: Color {
        switch self {
        case .sleep: Theme.Accent.nightText
        default: accent
        }
    }
}
