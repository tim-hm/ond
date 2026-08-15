import Foundation

/// How the breath is shaped on its way through, where [`Passage`] says where it
/// goes.
///
/// The pair answers the two halves of one question and a technique can turn on
/// either. Alternate-nostril breathing is the passage; the cooling breath is the
/// manner — it is a mouth inhale like nothing else in the catalogue, and "mouth"
/// is still not the thing that makes it that exercise. Said beside a breath, the
/// passage there was the true answer to a question nobody was asking.
///
/// It arrives from the catalogue rather than being asserted here, on `Passage`'s
/// reasoning: this app states no mechanic of its own, so a technique gains one
/// by being reseeded rather than by the app learning a slug.
///
/// The raw value is a stored key — the catalogue is cached on disk so the app
/// can breathe offline — and a synthesised case name is not a key that should
/// survive a refactor.
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
    /// The words to put beside a phase while somebody is breathing it.
    ///
    /// Not optional, which is the one place this parts from [`Passage.hint`].
    /// A passage has a silent case because most of the catalogue breathes
    /// through the nose and saying so every breath is the noise a hint line has
    /// to stay clear of; a manner is seeded only where the mechanic *is* the
    /// exercise, so there is no case worth suppressing and nothing a nil could
    /// mean.
    var hint: String {
        switch self {
        case .curledTongue: "Through a curled tongue"
        case .pursedLips: "Through pursed lips"
        case .hum: "Hum all the way out"
        }
    }

    /// The same where there is room for two words and no more — the wrist, and
    /// the lock screen's caption beside a technique name.
    ///
    /// It drops the preposition rather than truncating [`hint`], on
    /// `PhaseKind.shortInstruction`'s reasoning: "Through a curled ton…" is a
    /// phrase nobody reads at speed, and these surfaces are read at a glance or
    /// not at all.
    var glanceHint: String {
        switch self {
        case .curledTongue: "Curled tongue"
        case .pursedLips: "Pursed lips"
        case .hum: "Hum"
        }
    }
}

public extension Manner {
    /// "Breathe in through a curled tongue" — the how-to line for a phase done
    /// this way, or nil where this manner has nothing to say about this kind.
    ///
    /// A whole sentence replacing the breath's own rather than a clause appended
    /// to it, on `Breath.instruction`'s reasoning: "Breathe in through your
    /// mouth" plus "through a curled tongue" is English word order written into
    /// an interpolation, French and Japanese both reorder it, and a translator
    /// handed two fragments cannot fix that from the outside. Replacing also
    /// drops the mouth, which stops being the notable half of the breath the
    /// moment the tongue is named.
    ///
    /// Spelled against every combination rather than behind a `default`, so a
    /// manner added to the enum is a compile error here — the bar
    /// `playfulInstruction` holds itself to, and the reason the gaps below are a
    /// decision. A hold has no manner in any of them because air that is not
    /// moving is not being shaped. `hum` has no inhale because nobody teaches
    /// one, and a sentence nobody wrote is not one this app may assemble: that
    /// phase falls back to "Breathe in", which is true, rather than to a
    /// sentence invented here.
    ///
    /// Beside this manner's other words rather than in `TechniqueWords.swift`,
    /// on `Passage`'s arrangement: a decoded, seeded, per-phase enum keeps its
    /// vocabulary with it, and only the words of types that are *not* seeded
    /// live in that file.
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
