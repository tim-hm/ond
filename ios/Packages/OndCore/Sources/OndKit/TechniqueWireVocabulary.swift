import OndAPI

// How the wire's vocabulary becomes this app's, apart from the decoder that
// calls it — the same split `CatalogueExportVocabulary` makes for the bundled
// export, and for the same reason: the mappings are a table, and a table read
// beside the parsing it feeds is the parsing that gets skimmed.

extension Manner {
    /// How the breath was shaped, or nil for both unreadable wire values —
    /// which is where this parts from `Passage(breathing:)` below.
    ///
    /// `UNSPECIFIED` cannot be a failure here: it is the honest answer for all
    /// but three phases in the catalogue, where an unset passage on a moving
    /// breath is a contract violation.
    ///
    /// `UNRECOGNIZED` is a manner seeded after this build shipped, and it is nil
    /// rather than a throw on the arithmetic of what a throw would cost. A
    /// failure here fails the decode of its phase, its technique, and the whole
    /// `ListTechniques` response with it — so one newly seeded mechanic on one
    /// phase of one exercise would empty the catalogue on every older client. A
    /// hint line missing a sentence is the smaller loss by a wide margin, and it
    /// is a loss that repairs itself on update.
    ///
    /// The round trip `Passage` guards against does not reach here: the composer
    /// offers no manner, so a personal technique never carries one for an edit
    /// to overwrite.
    init?(proto: Ond_V1_Manner) {
        switch proto {
        case .curledTongue: self = .curledTongue
        case .pursedLips: self = .pursedLips
        case .hum: self = .hum
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension Breath {
    /// The kind and the passage the wire carries separately, resolved into the
    /// one case that can hold both.
    ///
    /// A hold never reads the passage — `Breath` has nowhere to put one, and
    /// `UNSPECIFIED` is exactly what a hold is contracted to carry — so the
    /// short-circuit is what keeps the contracted placeholder from reaching a
    /// decoder that refuses it. The passage a hold is handed instead is dropped
    /// by `Breath(kind:through:)`, which is what that initialiser documents.
    init(kind: PhaseKind, through proto: Ond_V1_Passage) throws {
        try self.init(kind: kind, through: kind.isHold ? .nose : Passage(breathing: proto))
    }
}

extension Passage {
    /// Where the air went on a breath that is moving.
    ///
    /// Neither unreadable wire value gets a passage of this app's choosing, and
    /// the reason is the round trip rather than the drawing. A passage somebody
    /// may have authored decodes through here, `TechniqueDraft(copying:)`
    /// rebuilds a draft from what came out, and saving that edit writes whatever
    /// this app guessed back over their own passage — so a guess does not
    /// mislabel a breath for one session, it overwrites the exercise.
    ///
    /// That holds for a case this build has no name for and for an unset one
    /// alike: the second is not a server predating the field so much as a
    /// breathing phase with no passage at all, which the contract does not admit
    /// and `0014_phase_passage.sql` refuses at the column. A hold's contracted
    /// `UNSPECIFIED` never arrives here — `Breath(kind:through:)` short-circuits
    /// it — so there is no case left that this can safely default.
    init(breathing proto: Ond_V1_Passage) throws {
        switch proto {
        case .nose: self = .nose
        case .mouth: self = .mouth
        case .leftNostril: self = .leftNostril
        case .rightNostril: self = .rightNostril
        case .unspecified:
            throw TechniqueRepositoryError.malformedResponse(
                "a breathing phase says nothing about where the air goes"
            )
        case .UNRECOGNIZED:
            throw TechniqueRepositoryError.malformedResponse(
                "unrecognised passage `\(proto)`"
            )
        }
    }

    var proto: Ond_V1_Passage {
        switch self {
        case .nose: .nose
        case .mouth: .mouth
        case .leftNostril: .leftNostril
        case .rightNostril: .rightNostril
        }
    }
}

extension FoundationTopic {
    /// Total, unlike the technique decoders: every field is a string this app
    /// only ever displays, so there is no value here it could fail to represent.
    init(proto: Ond_V1_FoundationTopic) {
        self.init(
            slug: proto.slug,
            question: proto.question,
            answer: proto.answer,
            answerContent: proto.hasAnswerContent
                ? ReadingContent(proto: proto.answerContent)
                : nil
        )
    }
}

extension TechniqueGoal {
    /// Returns nil for `UNSPECIFIED` and for any case added to the proto after
    /// this app shipped — both mean the same thing to a running client, and both
    /// must be a decode failure rather than a silent default.
    init?(proto: Ond_V1_TechniqueGoal) {
        switch proto {
        case .calm: self = .calm
        case .sleep: self = .sleep
        case .energy: self = .energy
        case .reset: self = .reset
        case .focus: self = .focus
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    /// The outbound direction, used by the profile a person picks their goals
    /// in. Here rather than there so that adding a goal is one file to find:
    /// both halves of this mapping have to change together, and the asymmetry
    /// over `unspecified` — rejected coming in, unrepresentable going out — is
    /// only reviewable if they sit next to each other.
    var proto: Ond_V1_TechniqueGoal {
        switch self {
        case .calm: .calm
        case .sleep: .sleep
        case .energy: .energy
        case .reset: .reset
        case .focus: .focus
        }
    }
}

extension EvidenceGrade {
    /// Nil for `UNSPECIFIED` and for a grade added after this app shipped, and
    /// — unlike every other `init?(proto:)` here — that nil is not a decode
    /// failure. An ungraded exercise is the ordinary case: it is what every
    /// exercise somebody composed carries, and what a newer server's third
    /// grade degrades to. The row then draws no chip, which is the honest
    /// rendering of "this build does not know how well evidenced that is".
    init?(proto: Ond_V1_EvidenceGrade) {
        switch proto {
        case .moderate: self = .moderate
        case .limited: self = .limited
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension PhaseKind {
    init?(proto: Ond_V1_PhaseKind) {
        switch proto {
        case .inhale: self = .inhale
        case .holdIn: self = .holdIn
        case .exhale: self = .exhale
        case .holdOut: self = .holdOut
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    /// The outbound direction, used by a technique somebody composed. Beside the
    /// inbound one for the reason `TechniqueGoal.proto` gives: both halves have
    /// to change together, and the asymmetry over `unspecified` is only
    /// reviewable if they sit next to each other.
    var proto: Ond_V1_PhaseKind {
        switch self {
        case .inhale: .inhale
        case .holdIn: .holdIn
        case .exhale: .exhale
        case .holdOut: .holdOut
        }
    }
}
