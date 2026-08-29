import OndKit
import SwiftUI

/// The breath as motion: one closed outline opens through the inhale, turns
/// through a hold, and closes through the exhale. Scale says how full the lungs
/// are; the turn only keeps a hold from looking frozen. Every value is a pure
/// function of `(breath, fullness, progress)` — a phase turns whole symmetry
/// steps, so nothing accumulates. Unit space is ±0.5, serving 260pt and 22pt.
public enum BreathFigure {
    /// How far a place sits from the middle at the top of a breath.
    static let openSpread: CGFloat = 0.43
    /// How far it sits from the middle at the bottom of one, under
    /// `Closure.dot`. Not zero: a point cannot show a rotation, so a hold at
    /// empty lungs would freeze — and at the 22 points an Island cue gets,
    /// this reach reads as the dot that cue wants.
    static let seedSpread: CGFloat = 0.095
    /// How far a place on the far side of the midline pulls in under
    /// `Bias.swell`. The far side shrinks rather than the near side growing, so
    /// the lean spends no room the figure does not have. Measured: past about a
    /// third the dent reads as damage rather than a lean, so this does not go
    /// up.
    static let swellTaper: CGFloat = 0.28
    /// How much of one blade's span `Bias.vent` opens, at full lungs. A
    /// fraction of a blade rather than a fixed angle, so the gesture matches
    /// any place count. Under 1 by construction, and that matters: a vent
    /// narrower than a blade swallows at most one corner, so the figure still
    /// reads as an aperture with a mouth rather than an arc.
    static let ventSpan: Double = 0.9

    /// The stroke a figure `size` points across is drawn at. Proportional with
    /// a floor: a purely proportional stroke is a third of a pixel at Island
    /// scale, and the floor keeps the miniature the same drawing rather than a
    /// fainter relative of it.
    public static func lineWidth(across size: CGFloat) -> CGFloat {
        max(size * 0.014, 1)
    }

    /// How much of the figure survives the bottom of a breath. A deliberate
    /// disagreement with the shipped orb, which never shrinks past
    /// `SessionTimeline.Beat.emptyLungs` because resting lungs still hold air;
    /// a breath arriving out of a seed is a reading of its own.
    public enum Closure: String, Sendable, CaseIterable {
        /// Down to a seed. Reads as the arrival of a breath rather than the
        /// bottom of one, and it is the geometry an Island cue has room for.
        case dot
        /// Down to the same fraction of full extent the orb stops at, so the
        /// closed figure still looks like lungs holding air.
        case lungs

        /// How far a place sits from the middle when the breath is at its
        /// emptiest.
        var closedSpread: CGFloat {
            switch self {
            case .dot: BreathFigure.seedSpread
            case .lungs: CGFloat(SessionTimeline.Beat.emptyLungs) * BreathFigure.openSpread
            }
        }
    }

    /// How fast the arrangement turns, and therefore how a phase paces.
    ///
    /// Both options turn a whole number of symmetry steps over any phase, which
    /// is what lets the spin start from zero each time instead of carrying a
    /// running total. They differ in whether emptying is livelier than filling.
    public enum Cadence: String, Sendable, CaseIterable {
        /// One step per phase, whatever the phase. The pace then reads phase
        /// *length* — a long exhale turns slowly — which says the least about
        /// which phase you are actually in.
        case even
        /// The rate follows lung fullness: one step per phase at the top of a
        /// breath, three at the bottom. The turn below is that rate integrated
        /// per phase. Every phase still lands on a whole step, so nothing
        /// accumulates; and the rate matches across every boundary, so the pace
        /// changes without the figure ever visibly stuttering.
        case momentum

        /// Symmetry steps turned by `progress` of the way through a phase.
        ///
        /// The linear fill rather than the eased one, because that is the
        /// integral that has an elementary form — and the easing belongs to how
        /// the figure looks, not to how far it has got.
        func turn(for kind: PhaseKind, at progress: Double) -> Double {
            switch self {
            case .even: progress
            case .momentum:
                switch kind {
                case .inhale: 3 * progress - progress * progress
                case .holdIn: progress
                case .exhale: progress + progress * progress
                case .holdOut: 3 * progress
                }
            }
        }
    }

    /// How the figure says which nostril the air is going through. Every
    /// option bends geometry rather than ink — nothing fades a stroke, so the
    /// exhale's measured 3:1 carries over untouched — and every one is
    /// extent-neutral, because size already means lung fullness. All scale with
    /// bloom, so the seed stays symmetric whichever nostril inhales next.
    public enum Bias: String, Sendable, CaseIterable {
        /// No asymmetry. What every technique breathing through the nose or the
        /// mouth draws.
        case centred
        /// Places on the far side pull in, so the figure looks fuller where the
        /// air is going. Reads without needing a reference, which a translation
        /// cannot do — but only faintly on an outline, where it dents a couple
        /// of corners and leaves a hexagon looking like a hexagon.
        case swell
        /// The arrangement turns towards the breathing side. Costs no geometry,
        /// but has to be learnt rather than seen, and it is the one asymmetry
        /// Reduce Motion deletes, because the turn is the whole of it.
        case spin
        /// The outline opens on the breathing side and stays shut on the other:
        /// a break in the line rather than a distortion, and a picture of what
        /// the hand is doing. The opening stays put while the arrangement turns
        /// through it; a mark fixed to a blade would travel. Costs: no longer a
        /// closed shape, and at Island scale the gap nearly vanishes.
        case vent
    }

    /// The knobs a treatment is chosen with — here so a prototype can compare
    /// the choices side by side, not because a shipping figure should be
    /// configurable. The defaults are what would ship.
    public struct Configuration: Sendable, Equatable {
        /// How many places the arrangement has, and so how many sides the
        /// aperture has. Six balances reading as an opening against a small
        /// pivot per symmetry step. Clamped in `didSet`, not only in the
        /// initialiser: a picker binds straight to this `var`, and two places
        /// make a line rather than an opening, which traps rather than degrades.
        public var places: Int {
            didSet { places = max(places, 3) }
        }

        public var closure: Closure
        public var cadence: Cadence
        public var bias: Bias

        public init(
            places: Int = 6,
            closure: Closure = .dot,
            cadence: Cadence = .even,
            bias: Bias = .vent
        ) {
            self.places = max(places, 3)
            self.closure = closure
            self.cadence = cadence
            self.bias = bias
        }
    }

    /// The figure at one instant. `fullness` is
    /// `SessionTimeline.Beat.lungFullness`, so the figure and the shipped orb
    /// share one easing; `progress` drives the turn, which a hold needs since
    /// it moves no air; `side` comes from `Stage.signedPhases`, so an exhale
    /// stays on its inhale's side; `reduceMotion` suppresses only the turn.
    public static func pose(
        for breath: Breath,
        fullness: Double,
        progress: Double,
        side: Passage.Side? = nil,
        reduceMotion: Bool = false,
        configuration: Configuration = Configuration()
    ) -> Pose {
        let bloom = SessionTimeline.Beat.level(ofFullness: fullness)
        let step = 360.0 / Double(configuration.places)
        let steps = configuration.cadence.turn(for: breath.kind, at: clamped(progress))
        // `Passage.Side.left` is +1 and the practitioner's left is drawn on the
        // viewer's left, where x runs negative — so the sign flips on its way
        // from the passage to the screen.
        let winding: Double = configuration.bias == .spin ? -(side?.rawValue ?? -1) : 1
        let turn = step * steps * winding

        return Pose(
            bloom: bloom,
            spin: reduceMotion ? .zero : .degrees(turn),
            side: side,
            configuration: configuration
        )
    }

    /// The figure with no session running: the seed, at the bottom of a breath.
    ///
    /// The state the Island cue draws between phases and the state a resting
    /// home screen draws, which is the same state — this is where the miniature
    /// and the full figure meet.
    public static func seed(configuration: Configuration = Configuration()) -> Pose {
        Pose(bloom: 0, spin: .zero, side: nil, configuration: configuration)
    }

    /// Phases stroke the technique drawings' four inks, whose WCAG 3:1
    /// softening is measured against `Theme.Surface.ground` — so a screen
    /// wearing `accentGround(_:)` puts the ground back with
    /// `figureGround(across:)` before stroking. The numbers, and the test that
    /// holds them, are in `ThemeColorTests`.
    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
