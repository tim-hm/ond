import OndUI
import SwiftUI

/// Three takes on the same dial, so the choices in it can be reacted to rather
/// than argued about.
///
/// Each one is a complete answer to the four questions the mechanism leaves
/// open — how far apart the detents sit, how many neighbours survive, whether
/// the focused stop grows, and what the tick feels like — because those
/// questions are not independent. A tight detent wants a light tick and legible
/// neighbours; a wide one wants a knock and a single neighbour turning away.
/// Splitting them into four switches would offer combinations that are nobody's
/// design.
///
/// Prototype scaffolding. Two of these are meant to be deleted, along with the
/// switch that reaches them.
enum DialTreatment: String, CaseIterable, Identifiable {
    /// A list that snaps. The detents are close, four neighbours stay fully
    /// legible, nothing grows, and the tick is the lightest the system has —
    /// the reading is that you are moving a selection, not turning a wheel.
    case column

    /// A drum. The detents are far apart, one neighbour either side turns away
    /// and the rest are gone, the focused stop grows, and the tick is a light
    /// knock. The most physical of the three and the closest to the crown.
    case wheel

    /// A slot you read one thing through. Middling detents, neighbours reduced
    /// to a hint, a small growth on focus, and a rigid tick. The most minimal —
    /// and the one that most nearly hides that there is a list at all.
    case aperture

    var id: Self {
        self
    }

    /// What the switch calls it.
    var title: String {
        rawValue
    }

    /// One detent's share of the dial, in points. The single number that most
    /// changes how the dial feels: it is the travel between ticks, so it sets
    /// how fast the taps arrive under a given flick.
    var slot: CGFloat {
        switch self {
        case .column: 54
        case .wheel: 92
        case .aperture: 68
        }
    }

    /// How many detents the window shows, focused one included. Always odd, so
    /// the focused stop has the same number of neighbours above and below —
    /// which is also what puts it in the middle of the window.
    var slots: Int {
        switch self {
        case .column: 5
        case .wheel: 3
        case .aperture: 3
        }
    }

    /// How much of a neighbour is left by the time it reaches the edge of the
    /// window: 0 is invisible, 1 is untouched. What "how much shows" comes down
    /// to once the slot count has decided how many are on screen at all.
    var peek: Double {
        switch self {
        case .column: 0.45
        case .wheel: 0.30
        case .aperture: 0.10
        }
    }

    /// How much larger the focused stop is drawn than its neighbours. 1 is the
    /// answer "it does not grow" — the column marks focus with ink and weight
    /// alone.
    var focusScale: CGFloat {
        switch self {
        case .column: 1
        case .wheel: 1.18
        case .aperture: 1.08
        }
    }

    /// How much of the window's top and bottom the fade eats, as a fraction of
    /// its height.
    ///
    /// Drawn rather than left to the scroll transition because the transition is
    /// motion and Reduce Motion drops it: without a mask, a dial with the
    /// effects off shows three or five equally solid rows and stops reading as a
    /// window onto one. This is the part of "how much of a neighbour shows" that
    /// survives that setting.
    var maskEdge: Double {
        switch self {
        case .column: 0.12
        case .wheel: 0.22
        case .aperture: 0.34
        }
    }

    /// Whether neighbours turn away from the reader on the way past. The
    /// perspective is what makes a wheel read as a cylinder rather than a
    /// fading list, and it is the one effect that is pure motion — Reduce
    /// Motion drops it wherever it is asked for.
    var turnsAway: Bool {
        self == .wheel
    }

    /// The tap as the dial crosses a detent.
    ///
    /// Matched to the metaphor rather than held constant: `.selection` is the
    /// lightest thing the system has and is what a snapping list should feel
    /// like, while a drum wants a knock with some body to it. Which of these is
    /// right is exactly the question a simulator cannot answer.
    var detent: SensoryFeedback {
        switch self {
        case .column: .selection
        case .wheel: .impact(weight: .light, intensity: 0.7)
        case .aperture: .impact(flexibility: .rigid, intensity: 0.5)
        }
    }

    /// The window's height — every treatment's dial occupies roughly the same
    /// band of the screen, so switching between them compares the dials rather
    /// than the layouts around them.
    var height: CGFloat {
        slot * CGFloat(slots)
    }

    /// How far the scroll content is inset so the first and last stops can
    /// reach the middle. Exactly the slots above the focused one — without it
    /// the dial would stop with the lead still at the top of the window.
    var margin: CGFloat {
        slot * CGFloat(slots - 1) / 2
    }
}
