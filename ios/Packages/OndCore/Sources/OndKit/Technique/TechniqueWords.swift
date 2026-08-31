import Foundation

// What a technique and its phases are *called*, apart from the model that
// carries them: the words and the shape change for different reasons, and
// only the shape is a contract with the server. Nothing here is decoded,
// stored, or sent.

public extension EvidenceGrade {
    /// What a chip prints: plain language rather than a grade. A rubric önd
    /// does not publish reads as a systematic review, and the two words a chip
    /// has room for cannot carry one. The fuller picture stays on the exercise
    /// page, which says what the studies actually were. Here rather than at the
    /// call sites so the three surfaces that draw one cannot disagree.
    var title: String {
        switch self {
        case .moderate: "Well studied"
        case .limited: "Early research"
        }
    }
}

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

    /// The goal as the person would say it, without an "I want to" in front.
    /// One word each, so a row of all five reads at a glance.
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

    /// What to do, on screen: two words, present tense. Through the nose,
    /// because a kind with no passage to state and a nose breath are the same
    /// sentence — the passage `Passage.hint` leaves unnamed.
    var instruction: String {
        Breath(kind: self, through: Passage.nose).instruction
    }

    /// The shortest cut of the instruction — the text of the voice manifest's
    /// short clips. `VoiceCoverageTests` pins the rendered clips to these
    /// words, so a change here is a re-render, not a copy edit. It drops the
    /// verb rather than truncating: "Breathe i…" reads as nothing at speed.
    var shortInstruction: String {
        switch self {
        case .inhale: "In"
        case .holdIn, .holdOut: "Hold"
        case .exhale: "Out"
        }
    }

    /// The phase named where nothing around it says which one it is — a row
    /// in a list of all four rather than a cue in a sequence. Only the holds
    /// differ from `instruction`: a cue can leave them alike because a hold
    /// is only reached from the breath before it, but an editing screen shows
    /// a whole cycle at once with no order to lean on.
    var standaloneTitle: String {
        switch self {
        case .holdIn: "Hold, lungs full"
        case .holdOut: "Hold, lungs empty"
        case .inhale, .exhale: instruction
        }
    }

    /// "Lungs full" — which hold this is, for the line under the cue. Its own
    /// switch rather than a clause sliced off [`standaloneTitle`]: a test
    /// pins the two literals to each other, so retuning one without the other
    /// fails there rather than drifting here. Nil for a moving breath, which
    /// has a passage or a manner to say instead.
    var lungsState: String? {
        switch self {
        case .holdIn: "Lungs full"
        case .holdOut: "Lungs empty"
        case .inhale, .exhale: nil
        }
    }
}

public extension Breath {
    /// "Breathe in through your left nostril" — one phase, in the words it is
    /// read, announced and spoken in. One sentence per case, never fragments
    /// joined at the call site: a whole sentence is the unit a translation is
    /// written in and a voice clip is recorded in. The nose stays unnamed;
    /// both holds read alike, and the sequence carries which one you are in.
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

    /// The breath this one is *said* as. A mouth breath speaks as a plain
    /// one: a cue is heard at the top of a breath already being taken, and
    /// "through your mouth" arrives too late — the read how-to keeps the
    /// mouth. The nostrils survive: alternate-nostril breathing is four
    /// phases that differ by nothing else.
    var spokenAs: Breath {
        switch self {
        case .inhale(.mouth): .inhale(through: .nose)
        case .exhale(.mouth): .exhale(through: .nose)
        case .inhale, .exhale, .holdIn, .holdOut: self
        }
    }

    /// What a cue says for this breath — the words the clip holds. Separate
    /// from `instruction` because the spoken and printed forms drift apart in
    /// exactly one place, said by `spokenAs`. `VoiceCoverageTests` holds the
    /// rendered audio to this, the one definition of what a voice may say.
    func spoken(in register: CopyRegister = .plain) -> String {
        playfulInstruction(in: register) ?? spokenAs.instruction
    }

    /// This breath's own words in `register`, or nil where it falls back.
    ///
    /// Asked of the breath as authored rather than of `spokenAs`, so a playful
    /// *mouth* exhale falls back to "Breathe out" rather than being handed
    /// "Blow out the candle" by way of the nose.
    func playfulInstruction(in register: CopyRegister) -> String? {
        switch register {
        case .plain: nil
        case .playful: playfulInstruction
        }
    }

    /// The same sentence, in the register the route asked for. A register
    /// covers only the breaths it was written for; every other breath keeps
    /// the plain sentence, which is the behaviour rather than a gap in it.
    func instruction(in register: CopyRegister) -> String {
        switch register {
        case .plain: instruction
        case .playful: playfulInstruction ?? instruction
        }
    }

    /// The same, as the screen shows it — `PhaseKind.instruction`'s form,
    /// which drops the passage. Derived from the whole breath, not its kind:
    /// only the breath knows whether the register covers it, and deriving
    /// through the nose once handed "Blow out the candle" to a mouth exhale
    /// on screen while the spoken form correctly fell back.
    func writtenInstruction(in register: CopyRegister) -> String {
        switch register {
        case .plain: kind.instruction
        case .playful: playfulInstruction ?? kind.instruction
        }
    }

    /// This breath as a small child can follow it, or nil where nobody wrote
    /// one. Spelled against every case rather than behind a `default`, so a
    /// new breath is a compile error, not a silent fallback. The gaps are
    /// decisions: the exercise this register exists for has no holds, and
    /// nostril steering is not what "smell the flower" is for.
    private var playfulInstruction: String? {
        switch self {
        case .inhale(.nose): "Smell the flower"
        case .exhale(.nose): "Blow out the candle"
        case .inhale(.mouth), .inhale(.leftNostril), .inhale(.rightNostril): nil
        case .exhale(.mouth), .exhale(.leftNostril), .exhale(.rightNostril): nil
        case .holdIn, .holdOut: nil
        }
    }
}

public extension CopyRegister {
    /// What the three-second countdown asks for before a session starts.
    /// Here rather than in `CountdownView` because the app target has no test
    /// bundle. Exhaustive in both lines, so a third register cannot inherit
    /// somebody else's words; the playful pair addresses the two of them.
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

public extension Technique {
    /// One cycle as a list reads it — "4 in, 7 hold, 8 out" — or, for a
    /// staged protocol, the shape of the whole thing: "3 rounds, you end the
    /// holds". In OndKit so the Exercises row and Home's sheet cannot
    /// describe one exercise two ways.
    var rhythmLine: String {
        rhythmParts.joined(separator: ", ")
    }

    /// ``rhythmLine``'s parts, one per phase — "5.5 in", "5.5 out" — for a
    /// row that sets them with its own separator and appends the length.
    var rhythmParts: [String] {
        guard !isStaged, let stage = stages.first else {
            let unit = recommendedRounds == 1 ? "round" : "rounds"
            let shape = hasOpenEndedStage ? "you end the holds" : "\(stages.count) stages"
            return ["\(recommendedRounds) \(unit)", shape]
        }

        return stage.phases
            .map { "\($0.duration.inSeconds) \($0.kind.shortInstruction.lowercased())" }
    }
}
