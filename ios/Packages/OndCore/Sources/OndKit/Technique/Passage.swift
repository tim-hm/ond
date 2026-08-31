import Foundation

/// Where the air goes on its way in or out. The second half of what a phase
/// is, and what makes alternate-nostril breathing that exercise rather than a
/// 4:6:4:6 rhythm. It arrives from the catalogue. The raw value is a stored
/// key, because the catalogue is cached on disk so the app can breathe
/// offline.
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
    /// where naming the passage would repeat what everybody already does.
    /// Nil for the nose, which most seeded techniques use throughout: a
    /// reminder on every breath is noise the hint line must stay clear of.
    var hint: String? {
        self == .nose ? nil : title
    }

    /// The letter a figure writes on the line — `L`, `R` or `M` — or nil where
    /// the air goes where a reader already assumes it goes. Lettered exactly
    /// where [`hint`] names a passage, which `everyLetteredPassageIsAlsoHinted`
    /// holds; a manner, a hold and a fast cycle reach that line unlettered.
    /// Written out, not read off `title`, so rewording cannot redraw a figure.
    var mark: String? {
        switch self {
        case .nose: nil
        case .mouth: "M"
        case .leftNostril: "L"
        case .rightNostril: "R"
        }
    }

    /// Which side of the midline a breath through this passage is drawn on, or
    /// nil for a passage that is not a side. A value, not something parsed out
    /// of `title`: it decides the shape of the drawing, and rewording or
    /// translating that string would silently redraw the figure.
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

/// One phase and the side of the midline its line is drawn on. A pair rather
/// than a second collection read alongside the phases, so nothing can pass on
/// a set of sides that no longer describes the phases beside it.
public struct SignedPhase: Sendable, Hashable {
    public let phase: Phase
    public let side: Passage.Side
}

public extension Stage {
    /// Each phase with the side of the midline it is drawn on, or nil where
    /// this stage has no sides and draws one-sided against a baseline. Per
    /// stage, so stage zero's sides cannot reach stage two's phases. Signed
    /// per breath by the nostril the inhale uses: signing each phase would
    /// cross the midline at full lungs and draw a jump the exercise has not.
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
