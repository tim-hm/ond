import Foundation

// What a technique and its phases are *called* — the words, kept apart from the
// model that carries them.
//
// Its own file because `Technique.swift` is the shape of a session and this is
// the vocabulary drawn over it: the two change for different reasons, and only
// one of them is a contract with the server. Nothing here is decoded, stored, or
// sent — a phrase can be retuned without a thought for the wire.

public extension TechniqueGoal {
    var title: String {
        switch self {
        case .calm: "Calm"
        case .sleep: "Sleep"
        case .energy: "Energy"
        case .reset: "Reset"
        case .focus: "Focus"
        }
    }

    /// The goal as the person would say it, without an "I want to" in front —
    /// the word a card, a row's caption and the composer's picker use. One word
    /// each, so a row of all five reads at a glance.
    ///
    /// There was a full-sentence `intent` beside this ("I want to relax") for the
    /// catalogue's per-goal section headers. Those headers are gone — the word
    /// travels in each row's caption now — and the sentence went with them rather
    /// than staying as a public API documented against a screen that no longer
    /// exists.
    var intentObject: String {
        switch self {
        case .calm: "relax"
        case .sleep: "sleep"
        case .energy: "wake"
        case .reset: "reset"
        case .focus: "focus"
        }
    }
}

public extension PhaseKind {
    /// Whether the breath is being held rather than moving.
    ///
    /// The distinction both breath guides key their colour off: a hold is the
    /// one phase where nothing is scaling, so with cues off the colour is all
    /// that marks the change.
    var isHold: Bool {
        switch self {
        case .holdIn, .holdOut: true
        case .inhale, .exhale: false
        }
    }

    /// What to do, on screen. Two words, present tense, legible at a glance
    /// through half-closed eyes.
    var instruction: String {
        switch self {
        case .inhale: "Breathe in"
        case .holdIn: "Hold"
        case .exhale: "Breathe out"
        case .holdOut: "Hold"
        }
    }

    /// The same instruction where there is room for one word and no more — the
    /// Dynamic Island's compact region, which is about as wide as a word.
    ///
    /// Short enough that it is read rather than parsed, which is the bar a
    /// glance cue has to clear. It drops the verb rather than truncating
    /// `instruction`, because "Breathe i…" is a word nobody reads at speed.
    var shortInstruction: String {
        switch self {
        case .inhale: "In"
        case .holdIn, .holdOut: "Hold"
        case .exhale: "Out"
        }
    }

    /// What VoiceOver announces. Longer than `instruction` because the two holds
    /// read identically aloud, and someone who cannot see the orb has only this
    /// to tell them which one they are in.
    var spokenInstruction: String {
        switch self {
        case .inhale: "Breathe in"
        case .holdIn: "Hold, lungs full"
        case .exhale: "Breathe out"
        case .holdOut: "Hold, lungs empty"
        }
    }
}

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
    /// What stands where a count would, on a stage the person ends rather than the
    /// clock.
    ///
    /// One spelling, because the two screens that state it are one tap apart: the
    /// steps under the figure and the Customise dials, which shows it where a
    /// stepper would be. `TechniqueFigure`'s description says the same thing in a
    /// sentence — "hold, for as long as you can" — and is deliberately not this: it
    /// is heard rather than read, mid-clause, where a bare "you decide" is a phrase
    /// with nothing to attach to.
    static var openEndedCount: String {
        "you decide"
    }

    /// The stage as lines somebody follows, in play order.
    ///
    /// Here rather than in the view that draws them, for the reason the rest of
    /// this file exists: naming a passage is a curation rule over the whole
    /// seeded catalogue — nine exercises, two of them exceptions — and the app
    /// target has no test bundle to check one in.
    ///
    /// This replaced a single `passageNote` sentence saying "In through your
    /// nose, out through your mouth" for the whole exercise. Said per phase it
    /// costs no more room and answers the case that sentence gave up on:
    /// alternate-nostril breathing changes nostril mid-cycle, which one sentence
    /// cannot state without being wrong, and a line per phase simply says which.
    ///
    /// An open-ended stage takes words rather than a number, the same hedge
    /// `TechniqueFigure`'s description makes: the session clock stops for a
    /// retention, so its authored duration describes a typical hold rather than a
    /// scheduled one, and a figure printed here would be a count nothing keeps.
    var steps: [BreathStep] {
        phases.enumerated().map { index, phase in
            BreathStep(
                instruction: phase.breath.writtenInstruction,
                count: openEnded ? Self.openEndedCount : phase.duration.counted,
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
        return "\(count), about \(plannedDuration.spelled). However many you do is the practice."
    }

    /// The fullest thing the exercise has to say about itself, or nil where it has
    /// nothing — the one block of prose its screen closes on.
    ///
    /// A curated exercise explains why it works. One somebody wrote has no
    /// mechanism, so it closes on the description its author typed, and on nothing
    /// where they skipped the field.
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
