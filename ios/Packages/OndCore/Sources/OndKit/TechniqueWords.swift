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
    ///
    /// The breath through the nose, because that is the passage `Passage.hint`
    /// leaves unnamed: a kind with no passage to state and a nose breath are the
    /// same sentence, and saying it twice is what `Breath` exists to stop.
    var instruction: String {
        Breath(kind: self, through: Passage.nose).instruction
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

    /// The phase named where nothing around it says which one it is — a row in
    /// a list of all four, rather than a cue in a sequence.
    ///
    /// Only the holds differ from `instruction`, and only because they are the
    /// pair that reads alike. A session can leave them alike: a hold is only
    /// ever reached from the breath before it, so the order says which you are
    /// in. An editing screen shows a whole cycle at once with no order to lean
    /// on, and two rows both reading "Hold" are two rows nobody can tell apart
    /// — including the one they meant to dial.
    var standaloneTitle: String {
        switch self {
        case .holdIn: "Hold, lungs full"
        case .holdOut: "Hold, lungs empty"
        case .inhale, .exhale: instruction
        }
    }
}

public extension Breath {
    /// "Breathe in through your left nostril" — one phase, in the words it is
    /// read, announced and spoken in.
    ///
    /// One sentence per case, not a kind and a passage joined at the call site.
    /// The join was English word order written into an interpolation — French
    /// and Japanese both reorder it, and a translator handed two fragments has
    /// no way to fix that from the outside. A whole sentence is the unit a
    /// translation is written in, and it is also the unit a voice clip is
    /// recorded in.
    ///
    /// One property rather than a read form and a heard form. They were two
    /// until the holds stopped saying which lungs state they were — "hold,
    /// lungs full" is not a thing anybody says out loud — at which point every
    /// case spelled the same sentence twice, which is the drift this file
    /// exists to prevent. Should a translation ever need the two to diverge,
    /// split it then and let the compiler find the call sites.
    ///
    /// The nose says nothing about the passage: it is what the foundations
    /// teach and what seven of the nine seeded exercises do throughout, so
    /// naming it on every breath is the noise that stops the nostrils being
    /// noticed when they matter.
    ///
    /// The two holds now read alike, which costs VoiceOver the one signal that
    /// told them apart when the orb cannot be seen. The sequence carries it
    /// instead — a hold is only ever reached from the breath before it.
    var instruction: String {
        switch self {
        case .inhale(.nose): "Breathe in"
        case .inhale(.mouth): "Breathe in through your mouth"
        case .inhale(.leftNostril): "Breathe in through your left nostril"
        case .inhale(.rightNostril): "Breathe in through your right nostril"
        case .holdIn, .holdOut: "Hold"
        case .exhale(.nose): "Breathe out"
        case .exhale(.mouth): "Breathe out through your mouth"
        case .exhale(.leftNostril): "Breathe out through your left nostril"
        case .exhale(.rightNostril): "Breathe out through your right nostril"
        }
    }
}

public extension CopyRegister {
    /// What the three-second countdown asks for before a session starts.
    ///
    /// Here rather than in `CountdownView` for the reason the rest of this file
    /// exists: the app target has no test bundle, and a register with a line
    /// missing is a blank heading over a counting numeral. Exhaustive over the
    /// register in both, so a third one cannot inherit somebody else's words.
    ///
    /// The playful pair addresses the two of them rather than the one holding
    /// the phone — the whole difference between this session and every other —
    /// and "ready" rather than "starting", which is a word about a machine.
    var settlingLine: String {
        switch self {
        case .plain: "Get comfortable"
        case .playful: "Get comfy together"
        }
    }

    /// The line the counting numeral finishes, and the lead VoiceOver hears once
    /// at three. Written to run straight into the number.
    var countdownLine: String {
        switch self {
        case .plain: "Starting in"
        case .playful: "Ready in"
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
    /// seeded catalogue — nine exercises, two of them exceptions — and the app
    /// target has no test bundle to check one in.
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
        phases.enumerated().map { index, phase in
            BreathStep(
                instruction: phase.breath.instruction,
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
