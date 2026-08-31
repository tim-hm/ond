import Foundation

/// A phase as the line under the cue reads it. A value rather than a computed
/// property, because the precedence *is* the feature and there are two
/// carriers in two processes — `SessionTimeline.Beat` and `SessionPresence` —
/// that must not drift. Kept apart from `Breath` and `BreathCueRole`, which
/// resolve copy for the same phase: merged, a cue changes when the pace does.
public struct BreathHint: Sendable, Hashable {
    public let manner: Manner?
    public let breath: Breath
    /// `Stage.breathesFast` — never `Beat.isFastRhythm`, which is a different
    /// threshold answering a different question, and true for a sigh.
    public let breathesFast: Bool

    public init(manner: Manner?, breath: Breath, breathesFast: Bool) {
        self.manner = manner
        self.breath = breath
        self.breathesFast = breathesFast
    }
}

public extension BreathHint {
    /// The line under the cue, or nil where this phase has nothing to add.
    /// Resolved most-specific first: the manner (seeded only where the
    /// mechanic is the whole point), the passage, the lungs state (the one
    /// rung that restates), then the pace (a fact about the stage, so it
    /// outranks nothing). Nil, not "", so a caller decides what a blank is.
    var line: String? {
        if let manner {
            return manner.hint
        }
        if let passage = breath.passage?.hint {
            return passage
        }
        if let lungs = breath.kind.lungsState {
            return lungs
        }
        return breathesFast ? Self.fastLine : nil
    }

    /// The same in the room a wrist or a lock-screen caption has. Only the
    /// manner has two lengths: every other rung is two words already, and a
    /// second spelling would be two strings to keep in step saying one thing —
    /// so every rung below the manner falls through to [`line`].
    var glance: String? {
        guard let manner else { return line }
        return manner.glanceHint
    }

    /// What the line adds that the spoken cue cannot already say, or nil. The
    /// passage rung is deliberately missing — the spoken cue already names the
    /// nostril. Exists so the ear keeps up with the screen: without it, humming
    /// breath's VoiceOver user is never told to hum. It stops at the passage
    /// rather than skip it, or "Mouth" would show while "Fast and even" spoke.
    var spokenAddition: String? {
        if let manner {
            return manner.hint
        }
        if breath.passage?.hint != nil {
            return nil
        }
        return line
    }

    /// "Fast and even" — derived from the rhythm rather than seeded: a seeded
    /// phrase would go on saying this after somebody slowed the exercise down.
    /// One value for every breath, because what is fast is the cycle.
    static let fastLine = "Fast and even"
}
