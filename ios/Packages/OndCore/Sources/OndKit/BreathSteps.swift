import Foundation

// The how-to an exercise prints: one line per phase, what to do set against how
// long for.
//
// Split from `TechniqueWords` when that file reached the length cap, and cut
// here because the seam is real: everything left there names a single thing —
// a goal, a phase, a breath — while this assembles those names into the rows a
// screen reads down. The vocabulary is the material; this is what is built from
// it.

/// One line of an exercise's how-to: what to do, and for how long.
///
/// A pair rather than one sentence, because the two are set against each other
/// on the row — the instructions read down the leading edge and the counts line
/// up on the trailing one, which is what makes four phases scan as a rhythm
/// instead of as four sentences.
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
    /// gives no typical band to print instead.
    ///
    /// One spelling, because the two screens that could state it are one tap
    /// apart: the steps under the figure and the Customise dials. Both prefer
    /// the phase's `band` — a hold bracketed by an example beats a shrug — so
    /// this survives only for an open phase whose range is a single point.
    static var openEndedCount: String {
        "you decide"
    }

    /// The stage as lines somebody follows, in play order.
    ///
    /// Here rather than in the view that draws them, for the reason the rest of
    /// this file exists: naming a passage is a curation rule over the whole
    /// seeded catalogue — where naming one is the exception — and the app target
    /// has no test bundle to check one in.
    ///
    /// This replaced a single `passageNote` sentence saying "In through your
    /// nose, out through your mouth" for the whole exercise. Said per phase it
    /// costs no more room and answers the case that sentence gave up on:
    /// alternate-nostril breathing changes nostril mid-cycle, which one sentence
    /// cannot state without being wrong, and a line per phase simply says which.
    ///
    /// An open-ended stage takes its range's band rather than its duration, the
    /// same hedge the figure's label makes: the session clock stops for a
    /// retention, so its dialled duration is the first round's aim rather than
    /// a scheduled length, and a count printed here would be one nothing keeps.
    /// The band brackets the hold instead — `30s–2m` — an example, not a
    /// promise.
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
    ///
    /// The counts are the *repetitions*, which the figure beside this sentence does
    /// not draw: it shows one cycle, or two of twenty-seven, and says which. An
    /// open-ended hold makes the total an estimate, and the sentence says so rather
    /// than printing a number the clock will not keep.
    ///
    /// Read it off a dialled technique. Every field it touches — cycles, rounds,
    /// the planned duration — is one a dial moves, so handed the curated entry it
    /// states a session nobody is about to breathe.
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

    /// The fullest thing the exercise has to say about itself, or nil where it has
    /// nothing — the source for its detail screen's explanatory topic.
    ///
    /// A curated exercise explains why it works. One somebody wrote has no
    /// mechanism, so its explanation is the description its author typed, and is
    /// absent where they skipped the field.
    ///
    /// Stated as a fallback rather than as a test of `origin`, which would agree
    /// with it today and stop agreeing the day the catalogue seeds an exercise
    /// nobody has written a mechanism for. Named here rather than decided in the
    /// view for the reason the rest of this file exists: it is a curation rule
    /// over the whole catalogue, and the app target has no test bundle.
    ///
    /// It also keeps the summary to one place on that screen. Under the steps it
    /// restated them — a first sentence counting out a rhythm the rows have just
    /// laid out as a column — and read a third time against a mechanism saying it
    /// again.
    var closingNote: String? {
        mechanism ?? summary.nilIfEmpty
    }
}
