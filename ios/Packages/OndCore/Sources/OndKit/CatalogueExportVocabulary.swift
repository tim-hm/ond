import Foundation

// The seed's spellings of the vocabularies both decoding paths share.
//
// Split out of `CatalogueExport.swift` so that file stays about the shape of
// the export rather than about six enums, and because these are the only
// decoders in it that read a bare string: everything left there needs the
// `Exported…` structs, which are fileprivate to it on purpose.
//
// `SCREAMING_SNAKE_CASE` because that is what serde writes and what the
// Postgres enums hold — a Swift case name is a refactor away from changing,
// and these are keys.

extension DeliverySurface {
    init(exported: String) throws {
        switch exported {
        case "FULL_SCREEN": self = .fullScreen
        case "DISCREET": self = .discreet
        default: throw CatalogueExport.Failure.unknownSurface(exported)
        }
    }
}

extension CopyRegister {
    /// Refused rather than degraded to plain, unlike the wire's decoder. There
    /// the unreadable value means a newer server naming a tone this build has
    /// no word for, and dropping a working exercise over it would cost more
    /// than the tone. Here the export and the decoder ship in the same binary,
    /// so an unknown register is a broken build rather than a newer peer.
    init(exported: String) throws {
        switch exported {
        case "PLAIN": self = .plain
        case "PLAYFUL": self = .playful
        default: throw CatalogueExport.Failure.unknownRegister(exported)
        }
    }
}

extension EvidenceGrade {
    /// Refused rather than dropped, on `CopyRegister`'s reasoning: the export
    /// and this decoder ship in one binary, so a grade neither knows is a broken
    /// build. A *missing* grade is different and never reaches here — the
    /// column is nullable and an absent one stays nil.
    init(exported: String) throws {
        switch exported {
        case "MODERATE": self = .moderate
        case "LIMITED": self = .limited
        default: throw CatalogueExport.Failure.unknownEvidenceGrade(exported)
        }
    }
}

extension Manner {
    /// Absent means absent, which is where this parts from `Passage` below.
    ///
    /// A moving breath that names no passage is a broken export and throws;
    /// almost no phase names a manner, so nil here is the ordinary answer rather
    /// than a dropped field. An unrecognised *value*, though, is as much a
    /// broken artefact as an unknown passage — this reads a committed file
    /// regenerated from the seed by the same `mise run generate`, so the two
    /// cannot legitimately disagree, and a silent fallback would hide the one
    /// case that means they have.
    init(exported: String) throws {
        switch exported {
        case "CURLED_TONGUE": self = .curledTongue
        case "PURSED_LIPS": self = .pursedLips
        case "HUM": self = .hum
        default: throw CatalogueExport.Failure.unknownManner(exported)
        }
    }
}

extension Passage {
    init(exported: String) throws {
        switch exported {
        case "NOSE": self = .nose
        case "MOUTH": self = .mouth
        case "LEFT_NOSTRIL": self = .leftNostril
        case "RIGHT_NOSTRIL": self = .rightNostril
        default: throw CatalogueExport.Failure.unknownPassage(exported)
        }
    }
}

extension TechniqueGoal {
    /// The export speaks the contract's vocabulary — the Postgres enum's labels
    /// — which is deliberately not this type's raw value.
    init(exported: String) throws {
        switch exported {
        case "CALM": self = .calm
        case "SLEEP": self = .sleep
        case "ENERGY": self = .energy
        case "RESET": self = .reset
        case "FOCUS": self = .focus
        default: throw CatalogueExport.Failure.unknownGoal(exported)
        }
    }
}

extension PhaseKind {
    init(exported: String) throws {
        switch exported {
        case "INHALE": self = .inhale
        case "HOLD_IN": self = .holdIn
        case "EXHALE": self = .exhale
        case "HOLD_OUT": self = .holdOut
        default: throw CatalogueExport.Failure.unknownPhaseKind(exported)
        }
    }
}
