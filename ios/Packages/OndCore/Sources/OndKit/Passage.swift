import Foundation

/// Where the air goes on its way in or out.
///
/// The second half of what a phase is, and the thing that makes
/// alternate-nostril breathing that exercise rather than a 4:6:4:6 rhythm. It
/// arrives from the catalogue rather than being asserted here: this used to be a
/// slug-keyed table in the app, shape-checked against the technique it was
/// written from, and the shape check was the whole safety story. The seed states
/// it now, so there is nothing left to pin to the wrong breath.
///
/// The raw value is a stored key — the catalogue is cached on disk so the app
/// can breathe offline — and a synthesised case name is not a key that should
/// survive a refactor.
public enum Passage: String, Sendable, Hashable, Codable, CaseIterable {
    case nose
    case mouth
    /// Named from the practitioner's own body: the nostril under their left
    /// hand, not the one on a reader's left.
    case leftNostril
    case rightNostril
}

public extension Passage {
    /// What to call it in a picker — "Left nostril". Always a full answer, unlike
    /// `hint`, because a selector with a blank row is a selector with a bug.
    var title: String {
        switch self {
        case .nose: "Nose"
        case .mouth: "Mouth"
        case .leftNostril: "Left nostril"
        case .rightNostril: "Right nostril"
        }
    }

    /// The words to put beside a phase while somebody is breathing it, or nil
    /// where naming the passage would only repeat what everybody is already
    /// doing.
    ///
    /// Nil for the nose because it is what the foundations teach and what eight
    /// of the ten seeded techniques do throughout — a reminder on every breath
    /// of every exercise is noise, and noise is what a hint line has to stay
    /// clear of to be read at all when it matters.
    var hint: String? {
        self == .nose ? nil : title
    }

    /// The letter a figure writes on the line — `L` — or nil where there is no
    /// side to distinguish.
    ///
    /// Only the nostrils get one. A mouth exhale is already distinguished by
    /// being the exhale, and a letter marking every phase of every figure is a
    /// texture rather than a label.
    var mark: String? {
        side == nil ? nil : String(title.prefix(1))
    }

    /// Which side of the midline a breath through this passage is drawn on, or
    /// nil for a passage that is not a side.
    ///
    /// A value rather than something read back out of `title`: it decides the
    /// *shape* of the drawing, and parsing it out of "Left nostril" would mean
    /// rewording the sentence — or translating it — silently redraws the figure
    /// with nothing failing.
    var side: Side? {
        switch self {
        case .leftNostril: .left
        case .rightNostril: .right
        case .nose, .mouth: nil
        }
    }

    /// Which side of the midline a breath is drawn on. Left is positive because
    /// the catalogue's cycle starts there, so the figure opens by climbing — the
    /// same up-is-filling reading every other drawing has.
    enum Side: Double, Sendable, Hashable {
        case left = 1
        case right = -1
    }
}

public extension Breath {
    /// "Breathe in, left nostril" — one phase as it should be said aloud.
    ///
    /// One composition, because the same sentence is spoken twice about the same
    /// exercise: while somebody is choosing it (the figure's description) and
    /// while they are breathing it (the player's announcements). Two spellings
    /// of it would drift with nothing comparing them.
    var spokenInstruction: String {
        guard let hint = passage?.hint else { return kind.spokenInstruction }
        return "\(kind.spokenInstruction), \(hint.lowercased())"
    }

    /// "Breathe in through your left nostril" — the same phase as it is read
    /// rather than heard.
    ///
    /// Beside the spoken one and composed the same way, so the passage rule is
    /// stated once: the nose is silent here too, because `hint` is what decides
    /// it and a reminder on every line of every exercise is the noise that stops
    /// the nostrils being noticed when they matter.
    ///
    /// A preposition rather than the spoken version's comma. Somebody hearing a
    /// phase announced mid-breath needs the passage as an aside on the end of an
    /// instruction they are already following; somebody reading the how-to before
    /// they start is reading a sentence.
    var writtenInstruction: String {
        guard let hint = passage?.hint else { return kind.instruction }
        return "\(kind.instruction) through your \(hint.lowercased())"
    }
}

/// One phase and the side of the midline its line is drawn on.
///
/// A pair rather than a second collection read alongside the phases: the sides
/// are derived *from* the phases, and anything passing them onward separately
/// can pass on a set that no longer describes the phases beside it — a figure
/// drawn on the wrong side of its own line, with nothing to say so.
public struct SignedPhase: Sendable, Hashable {
    public let phase: Phase
    public let side: Passage.Side
}

public extension Stage {
    /// Each phase with the side of the midline it is drawn on — or nil where
    /// this stage has no sides to alternate between and draws one-sided against
    /// a baseline.
    ///
    /// Per stage rather than per technique, so a caller cannot hand stage zero's
    /// sides to stage two's phases. The flat version this replaced needed a
    /// guard rejecting every staged technique to stay safe, which quietly meant
    /// a staged protocol that alternated nostrils would draw one-sided and
    /// nothing would say so.
    ///
    /// Signed **per breath, by the nostril the inhale goes through** — not per
    /// phase. Alternate-nostril breathing changes nostril within a breath (in
    /// left, out right), so signing each phase separately would send the line
    /// across the midline at full lungs and draw a jump where the exercise has
    /// none. Taking the inhale's side for the exhale that empties it keeps every
    /// crossing at empty lungs, which is where the breath actually pauses.
    var signedPhases: [SignedPhase]? {
        guard phases.contains(where: { $0.passage?.side != nil }) else { return nil }

        var current = Passage.Side.left
        return phases.map { phase in
            if phase.kind == .inhale, let side = phase.passage?.side {
                current = side
            }
            return SignedPhase(phase: phase, side: current)
        }
    }
}
