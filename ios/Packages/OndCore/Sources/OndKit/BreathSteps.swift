import Foundation

// The how-to an exercise prints: one line per phase, what to do set against
// how long for. Everything in `TechniqueWords` names a single thing; this
// assembles those names into the rows a screen reads down.

/// One line of an exercise's how-to: what to do, and for how long. A pair
/// rather than one sentence, because the two are set against each other on
/// the row — instructions down the leading edge, counts on the trailing one —
/// which is what makes four phases scan as a rhythm.
public struct BreathStep: Sendable, Hashable, Identifiable {
    /// What to do — "Breathe in through your left nostril".
    public let instruction: String

    /// How long for — "4s", or the words an open-ended hold takes instead of a
    /// number.
    public let count: String

    /// Position within its own stage. A stage's steps are drawn as one group and
    /// never merged with another's, so this is unique wherever it identifies one.
    public let id: Int
}

public extension Stage {
    /// What stands where a count would, on an open-ended phase whose catalogue
    /// gives no typical band to print instead. One spelling, because the steps
    /// under the figure and the Customise dials are one tap apart; both prefer
    /// the phase's `band`, so this survives only where the range is a point.
    static var openEndedCount: String {
        "you decide"
    }

    /// The stage as lines somebody follows, in play order. Here rather than in
    /// the view: naming a passage is a curation rule over the whole catalogue,
    /// and the app target has no test bundle. Per phase, not one sentence —
    /// alternate-nostril breathing changes nostril mid-cycle. An open-ended
    /// stage prints its range's band (`30s–2m`): an example, not a promise.
    var steps: [BreathStep] {
        let cueRoles = cueRoles
        return phases.enumerated().map { index, phase in
            BreathStep(
                instruction: cueRoles[index].preparationInstruction(
                    for: phase.breath,
                    doneWith: phase.manner,
                    in: .plain
                ),
                count: openEnded
                    ? phase.range.band ?? Self.openEndedCount
                    : phase.duration.counted,
                id: index
            )
        }
    }
}

public extension Technique {
    /// How much of the exercise there is, at whatever dials this copy carries.
    /// The counts are the *repetitions*, which the figure does not draw. An
    /// open-ended hold makes the total an estimate, and the sentence says so.
    /// Read it off a dialled technique; handed the curated entry it states a
    /// session nobody is about to breathe.
    var doseDescription: String {
        guard !isStaged else {
            let rounds = recommendedRounds == 1 ? "One round" : "\(recommendedRounds) rounds"
            return hasOpenEndedStage
                ? "\(rounds), around \(plannedDuration.spelled) depending on how long your holds run."
                : "\(rounds), about \(plannedDuration.spelled)."
        }

        let cycles = stages.first?.cycles ?? 1
        let count = cycles == 1 ? "One cycle" : "\(cycles) cycles"
        return "\(count), about \(plannedDuration.spelled)."
    }

    /// The fullest thing the exercise says about itself, or nil — the source
    /// for its detail screen's explanatory topic. A curated exercise explains
    /// why it works; a written one falls back to its author's description. A
    /// fallback rather than a test of `origin`, which would stop agreeing the
    /// day the catalogue seeds an exercise with no written mechanism.
    var closingNote: String? {
        mechanism ?? summary.nilIfEmpty
    }
}
