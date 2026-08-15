import Foundation

/// A phase as the line under the cue reads it.
///
/// A value rather than a computed property on each carrier, because the
/// precedence *is* the feature and there are two carriers in two processes:
/// `SessionTimeline.Beat` in the app, `SessionPresence` on the lock screen. A
/// precedence respelled at each of them is the drift `Breath.instruction` was
/// collapsed into one property to prevent — and here it would show as one
/// session saying two things about one breath.
///
/// Three inputs rather than a `Phase`, because one of them is not a fact about
/// the phase: whether the breathing is fast is a property of the cycle around
/// it, and only the stage knows.
///
/// Kept apart from `Breath` and `BreathCueRole`, which also resolve copy for one
/// phase, and the three must stay apart. `Breath` is what the phase *is*,
/// `BreathCueRole` is what the phases around it make it, and this is what a
/// second line adds once the cue has said the first thing. Merging them means a
/// cue that changes when a stage's pace does.
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
    ///
    /// Resolved in order of specificity, each rung a strictly narrower claim
    /// than the one below it:
    ///
    /// 1. **The manner.** The cooling breath's inhale goes through the mouth
    ///    *and* through a curled tongue, and only one of those is the exercise.
    ///    The passage it displaces is never the more useful of the two, because
    ///    a manner is seeded only where the mechanic is the whole point.
    /// 2. **The passage**, which alternate-nostril breathing cannot be done
    ///    without. `Passage.hint` decides which passages are worth saying at all.
    /// 3. **The lungs state**, which the phase order already implies — see
    ///    `PhaseKind.standaloneTitle`. Below the two seeded rungs because it is
    ///    the only one that restates something rather than adding to it.
    /// 4. **The pace**, last because it is a fact about the stage rather than
    ///    the phase, and so cannot outrank anything the phase says about itself.
    ///
    /// Nil rather than an empty string, so a caller decides what a blank line
    /// is. Both session screens reserve its height with a space — see
    /// `SessionTimeline.hintsAnyBeat`.
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

    /// The same in the room a wrist or a lock-screen caption has.
    ///
    /// Only the manner has two lengths. "Left nostril", "Lungs full" and "Fast
    /// and even" are two words already, and a second spelling of them would be
    /// two strings to keep in step saying one thing — so every rung below the
    /// manner falls through to [`line`] rather than being restated here.
    var glance: String? {
        guard let manner else { return line }
        return manner.glanceHint
    }

    /// "Fast and even" — derived from the rhythm rather than seeded.
    ///
    /// The pace is arithmetic over durations a dial can move, so a seeded phrase
    /// would go on saying this after somebody slowed the exercise down. It is
    /// also the one rung with no per-phase source at all: every breath in a fast
    /// stage says the same thing, because what is fast is the cycle.
    static let fastLine = "Fast and even"
}
