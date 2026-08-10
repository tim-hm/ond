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

public extension Technique {
    /// What the exercise's own screen opens on: why it works, or — for an
    /// exercise somebody wrote — the description they typed, which is the only
    /// prose it has. The composer never asks an author for a mechanism;
    /// inviting one to assert physiology is not something this app should do.
    var opening: String {
        mechanism ?? summary
    }

    /// The summary, for the caption under the figure — or nil when `opening`
    /// already said it up top.
    ///
    /// The exact inverse of `opening`'s fallback, held beside it so the pair
    /// cannot drift: whichever way the mechanism question goes, the summary
    /// appears on the screen exactly once. The views render these; neither
    /// decides.
    var practiceSummary: String? {
        mechanism == nil ? nil : summary
    }

    /// Where the air goes, or nil where saying so would only name what everybody
    /// is already doing.
    ///
    /// Nil for nose-in-nose-out, which is `Passage.hint`'s rule and is asked in
    /// its terms: the nose is what the foundations teach and what most of the
    /// catalogue does throughout, so a line repeating it on every exercise is the
    /// noise that stops the other ones being read.
    ///
    /// Nil too where either direction uses more than one passage, which is
    /// alternate-nostril breathing and nothing else. One sentence cannot say
    /// "alternating, and which hand closes which" without being wrong, and that
    /// exercise's own summary says it properly.
    ///
    /// Here rather than in the view that draws it, because it is a rule over the
    /// whole seeded catalogue — nine exercises, one of them an exception — and the
    /// app target has no test bundle to check it in.
    var passageNote: String? {
        let phases = stages.flatMap(\.phases)
        let inhaled = Set(phases.filter { $0.kind == .inhale }.compactMap(\.passage))
        let exhaled = Set(phases.filter { $0.kind == .exhale }.compactMap(\.passage))

        guard inhaled.count == 1, exhaled.count == 1,
              let inhale = inhaled.first, let exhale = exhaled.first,
              inhale.hint != nil || exhale.hint != nil
        else {
            return nil
        }

        return "In through your \(inhale.title.lowercased()), "
            + "out through your \(exhale.title.lowercased())."
    }

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
}
