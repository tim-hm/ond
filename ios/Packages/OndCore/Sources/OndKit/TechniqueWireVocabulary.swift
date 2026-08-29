import OndAPI

// How the wire's vocabulary becomes this app's, apart from the decoder that
// calls it — the same split `CatalogueExportVocabulary` makes for the bundled
// export, and for the same reason: the mappings are a table, and a table read
// beside the parsing it feeds is the parsing that gets skimmed.

extension Manner {
    /// How the breath was shaped, or nil for both unreadable wire values.
    /// `UNSPECIFIED` is the honest answer for most phases. `UNRECOGNIZED` is
    /// nil, not a throw: a throw fails the whole `ListTechniques` response,
    /// emptying the catalogue on every older client. The round trip `Passage`
    /// guards against never reaches here — the composer offers no manner.
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
    /// The kind and the passage, resolved into the one case that holds both.
    /// A hold never reads the passage: `UNSPECIFIED` is exactly what a hold
    /// is contracted to carry, and the short-circuit keeps that placeholder
    /// from reaching a decoder that refuses it.
    init(kind: PhaseKind, through proto: Ond_V1_Passage) throws {
        try self.init(kind: kind, through: kind.isHold ? .nose : Passage(breathing: proto))
    }
}

extension Passage {
    /// Where the air went on a breath that is moving. Both unreadable wire
    /// values throw. The round trip is why: a decoded guess is rebuilt into a
    /// draft, and saving that edit writes the guess back over the author's
    /// own passage. An unset passage on a moving breath violates the contract;
    /// a hold's `UNSPECIFIED` is short-circuited and never arrives here.
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
    /// Nil for `UNSPECIFIED` and for a grade added after this app shipped —
    /// and unlike every other `init?(proto:)` here, that nil is not a decode
    /// failure: an ungraded exercise is the ordinary case, and the row simply
    /// draws no chip.
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
