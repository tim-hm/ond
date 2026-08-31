import Foundation

/// How the breath is shaped on its way through, where [`Passage`] says where
/// it goes — the cooling breath is the manner, not its mouth inhale. It
/// arrives from the catalogue rather than being asserted here: this app
/// states no mechanic of its own. The raw value is a stored key — the
/// catalogue is cached on disk — and a case name is not a key.
public enum Manner: String, Sendable, Hashable, Codable, CaseIterable {
    /// Sitali's tube, drawn through a wet surface. Named for the shape the copy
    /// leads on; the technique's `preparation` is where the alternative for a
    /// tongue that will not roll survives, because a case cannot hedge.
    case curledTongue
    case pursedLips
    /// Not a passage: the air still leaves through the nose, and that is the
    /// only way a hum works at all.
    case hum
}

public extension Manner {
    /// The words to put beside a phase while somebody is breathing it. Not
    /// optional, unlike [`Passage.hint`]: a manner is seeded only where the
    /// mechanic *is* the exercise, so there is no case worth suppressing and
    /// nothing a nil could mean.
    var hint: String {
        switch self {
        case .curledTongue: "Through a curled tongue"
        case .pursedLips: "Through pursed lips"
        case .hum: "Hum all the way out"
        }
    }

    /// The two-word form for the wrist and the lock screen caption.
    ///
    /// It drops the preposition instead of truncating [`hint`], because these
    /// surfaces are read at a glance. See `PhaseKind.shortInstruction`.
    var glanceHint: String {
        switch self {
        case .curledTongue: "Curled tongue"
        case .pursedLips: "Pursed lips"
        case .hum: "Hum"
        }
    }
}

public extension Manner {
    /// The full how-to line for a phase done this way, or nil where this
    /// manner says nothing about this kind: a hold shapes no air, and nobody
    /// teaches a hummed inhale. A whole sentence replaces the breath's own
    /// line, because an appended clause writes English word order into an
    /// interpolation. Every pair is spelled out, so a new manner fails here.
    func instruction(for kind: PhaseKind) -> String? {
        switch (self, kind) {
        case (.curledTongue, .inhale): "Breathe in through a curled tongue"
        case (.curledTongue, .exhale): "Breathe out through a curled tongue"
        case (.pursedLips, .inhale): "Breathe in through pursed lips"
        case (.pursedLips, .exhale): "Breathe out through pursed lips"
        case (.hum, .exhale): "Breathe out, humming all the way"
        case (.hum, .inhale): nil
        case (_, .holdIn), (_, .holdOut): nil
        }
    }
}
