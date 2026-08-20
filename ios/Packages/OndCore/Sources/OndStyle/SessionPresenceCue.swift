import OndKit
import OndUI
import SwiftUI

/// The cue rules the pushed surfaces share — the lock screen's track and the
/// Island's minimal ring both style themselves off the presence, and
/// `ios/OndActivity/` has no test bundle, so a rule written twice there is a
/// decision nothing checks. Stated once here, where the suite reaches it —
/// `GoalAccent`'s reasoning, for the same surfaces.
public extension SessionPresence {
    /// The hold's indigo while a breath is held, the surface's accent while it
    /// moves — the shift every önd surface makes, so the Island and the screen
    /// mark a hold the same way. Not while paused: a paused cue says "Paused"
    /// rather than naming the phase, and a hold-coloured cue would go on
    /// asserting a hold nobody is in.
    func cueTint(over accent: Color) -> Color {
        Self.cueTint(breath: breath, isPaused: isPaused, over: accent)
    }

    /// The tint's arithmetic, on the two facts it actually reads — internal so
    /// the tests reach it without composing a whole presence, like
    /// `BreathGlyph.Pose.pushed(breath:isPaused:)`.
    internal static func cueTint(breath: Breath, isPaused: Bool, over accent: Color) -> Color {
        breath.kind.isHold && !isPaused ? Theme.Breath.hold : accent
    }
}

public extension Breath {
    /// Which way a timer-interval cue sweeps this breath: it fills as the
    /// lungs do and drains with them, so only an exhale counts down.
    var cueCountsDown: Bool {
        kind == .exhale
    }
}
