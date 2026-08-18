import OndKit
import SwiftUI

/// The breath as a motion language rather than one asset.
///
/// One arrangement — evenly spaced places at a reach from the middle, joined
/// into a closed outline — opening through the inhale, turning slowly through a
/// hold, and closing again through the exhale. The mapping is the whole idea:
/// geometry carries physiology, so the four `PhaseKind`s read apart before
/// colour is consulted.
///
/// | Phase     | Reach         | Turn                     |
/// | :-------- | :------------ | :----------------------- |
/// | `inhale`  | opening       | turning                  |
/// | `holdIn`  | wide, steady  | turning at full reach    |
/// | `exhale`  | closing       | turning                  |
/// | `holdOut` | tight, steady | turning at the seed      |
///
/// Scale is what says which half of the breath you are on, and it says it
/// loudly. The turn is there for one job only: nothing may freeze. A hold drawn
/// as a still shape is indistinguishable from an app that has stopped, and the
/// two holds are told apart by reach — wide against tight — rather than by
/// anything the rotation does. On the default six-sided aperture a phase pivots
/// sixty degrees, which registers as an edge being alive rather than as
/// spinning.
///
/// An aperture and nothing else. The first pass drew the same arrangement three
/// ways — this outline, a wheel with marks on it, and circles orbiting one
/// another — and the loud one separated the phases best while being a great deal
/// of movement to sit in front of for ten minutes. What settled it was that the
/// aperture's weakest point turned out not to be a property of quiet drawings at
/// all: the thing the rings did better was say which nostril, and `Bias.vent`
/// says that on an outline better than any of them said it with mass.
///
/// Every value here is a pure function of `(breath, fullness, progress)`, and
/// nothing accumulates across a session. That is a constraint rather than a
/// convenience: a phase turns a whole number of the arrangement's own symmetry
/// steps, so it comes home to a visually identical angle at each boundary and
/// the next phase can start from zero again. A free-running angle would need a
/// running total — a value free to drift, and a reason to keep recomputing while
/// nothing is happening.
///
/// The unit space is a square centred on the origin, extending to ±0.5, which is
/// what lets one arrangement serve a 260-point session figure and a 22-point
/// Dynamic Island cue without a second set of numbers.
public enum BreathFigure {
    /// How far a place sits from the middle at the top of a breath.
    static let openSpread: CGFloat = 0.43
    /// How far it sits from the middle at the bottom of one, under
    /// `Closure.dot`.
    ///
    /// Not zero, and this is the load-bearing small number in the whole figure.
    /// An arrangement with no reach is a point, and a point cannot show a
    /// rotation — so a hold at empty lungs would be the single motionless state
    /// in a language whose whole premise is that nothing freezes. It is also
    /// what makes one arrangement serve both scales: at 260 points it is a tight
    /// knot visibly turning, and at the 22 points a Dynamic Island cue gets it
    /// is two points across and reads as the dot that cue wants.
    static let seedSpread: CGFloat = 0.095
    /// How far a place on the far side of the midline pulls in under
    /// `Bias.swell`.
    ///
    /// The far side shrinks rather than the near side growing: the reading is
    /// "fuller where the air is going", and taking it out of the far side is the
    /// way to get it without spending room the figure does not have.
    ///
    /// Weaker than it looks, and that is measured rather than assumed — a
    /// symmetric outline dented on one side still reads mostly as a hexagon,
    /// which is why the vent exists. Past about a third the dent stops reading
    /// as a lean and starts reading as damage, so this does not go up.
    static let swellTaper: CGFloat = 0.28
    /// How much of one blade's span `Bias.vent` opens, at full lungs.
    ///
    /// A fraction of a blade rather than a fixed angle, so the opening is the
    /// same gesture whatever the arrangement is built from — a wide mouth on a
    /// triangle and a narrow one on an octagon are the same drawing at different
    /// resolutions. Under 1 by construction and that matters: a vent narrower
    /// than a blade can swallow at most one corner, so the figure always keeps
    /// enough outline to still read as an aperture with a mouth rather than as
    /// an arc.
    static let ventSpan: Double = 0.9

    /// The stroke a figure `size` points across is drawn at.
    ///
    /// Proportional with a floor rather than proportional alone: the same
    /// arrangement has to survive from a session figure down to an Island cue,
    /// and a purely proportional stroke is a third of a pixel by the time it
    /// gets there. The floor is what makes the miniature the same drawing rather
    /// than a smaller, fainter relative of it.
    public static func lineWidth(across size: CGFloat) -> CGFloat {
        max(size * 0.014, 1)
    }

    /// How much of the figure survives the bottom of a breath.
    ///
    /// A real disagreement with the shipped orb rather than a knob: the session
    /// orb never shrinks past `SessionTimeline.Beat.emptyLungs`, on the grounds
    /// that lungs at rest still hold air and a visual collapsing to a point says
    /// otherwise. The figure can say it differently, because a breath arriving
    /// out of a seed is a reading of its own — and the two look quite different.
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
        /// The rate is a function of how full the lungs are: one step per phase
        /// at the top of a breath, three at the bottom. A spin tightens when the
        /// arms come in, and this figure does the same — the collapse winds up,
        /// the bloom winds down, and the two holds separate by pace as well as by
        /// size.
        ///
        /// The turn below is that rate integrated, which is why it is written out
        /// per phase rather than derived at each frame. Two things fall out of
        /// it and both matter. Every phase still lands on a whole step, so
        /// nothing accumulates. And the rate matches across every boundary — a
        /// phase ending at full lungs hands over at one step, a phase ending at
        /// empty hands over at three — so the pace changes without the figure
        /// ever visibly stuttering, whichever phases a technique puts next to
        /// each other.
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

    /// How the figure says which nostril the air is going through.
    ///
    /// Every option is an asymmetry of the one arrangement rather than a second
    /// drawing, and every one is spent in geometry rather than in ink — nothing
    /// here fades a stroke, so the exhale's measured 3:1 against the ground
    /// carries over from the technique drawings untouched. Every one is also
    /// extent-neutral: a nostril must not resize the figure, because size
    /// already means how full the lungs are.
    ///
    /// All of them vanish as the breath empties, because all of them scale with
    /// bloom. That is what keeps the seed symmetric — the dot an Island cue
    /// draws is the same dot whichever nostril the next inhale goes through.
    public enum Bias: String, Sendable, CaseIterable {
        /// No asymmetry. What every technique breathing through the nose or the
        /// mouth draws.
        case centred
        /// Places on the far side pull in, so the figure looks fuller where the
        /// air is going. Reads without needing a reference, which a translation
        /// cannot do — but only faintly on an outline, where it dents a couple
        /// of corners and leaves a hexagon looking like a hexagon.
        case swell
        /// The arrangement turns towards the breathing side: the top travels
        /// left for the left nostril and right for the right. Costs no geometry
        /// at all, and pays for that twice — it has to be learnt rather than
        /// seen, since nothing on screen says which way is which, and it is the
        /// one asymmetry Reduce Motion deletes, because the turn is the whole of
        /// it.
        case spin
        /// The outline opens on the breathing side and stays shut on the other.
        ///
        /// The one that reads, and it reads because it is not a distortion of
        /// the shape but a break in the line — the strongest signal a stroke can
        /// carry, and the only one here that does not have to compete with the
        /// scaling that already means the breath. It is also a picture of the
        /// technique rather than a code for it: alternate-nostril breathing *is*
        /// one passage held closed while the other is open, so a figure sealed
        /// on one side and open on the other is saying exactly what the hand is
        /// doing.
        ///
        /// The opening stays put on the breathing side while the arrangement
        /// turns through it, which is what an aperture does and what a mark
        /// fixed to a blade could not: an opening that travelled would be
        /// pointing somewhere new every second.
        ///
        /// Two costs, both real. A vented figure is not a closed shape, so
        /// alternate-nostril breathing looks materially unlike every other
        /// technique — right, since it is unlike them, but a difference in kind
        /// rather than in degree. And at Island scale the gap is a couple of
        /// points of missing line, which is the one size where the swell's
        /// mass-shifting would have carried further.
        case vent
    }

    /// The knobs a treatment is chosen with. Present because this is a prototype
    /// and the choices below are the ones worth seeing side by side, not because
    /// a shipping figure should be configurable.
    ///
    /// The defaults are what would ship: a six-sided aperture, one symmetry step
    /// per phase, closing to a dot, venting towards the nostril.
    public struct Configuration: Sendable, Equatable {
        /// How many places the arrangement has, and therefore how many sides the
        /// aperture has.
        ///
        /// Six is a compromise between two things the outline wants in opposite
        /// directions: enough sides to read as an opening rather than as a
        /// triangle, and a small pivot, which is what more sides buy — a phase
        /// turns one symmetry step, so six sides pivot 60° where three pivot
        /// 120°.
        ///
        /// Clamped where it is written rather than only where it is first set:
        /// this is a `var` a picker binds straight to, so an initialiser's guard
        /// is one the next mutation walks past — and two places make a line
        /// rather than an opening, which traps rather than degrades.
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

    /// The figure at one instant of one phase.
    ///
    /// - Parameters:
    ///   - breath: What the breath is doing, and where the air is going.
    ///   - fullness: How full the lungs are — `SessionTimeline.Beat.lungFullness`
    ///     rather than a curve of this figure's own, so the figure and the
    ///     shipped orb are driven by one easing and cannot disagree about when
    ///     the top of a breath is.
    ///   - progress: How far through the phase, 0...1 —
    ///     `SessionTimeline.Beat.fraction`. Drives the turn, which is why it is
    ///     needed alongside `fullness`: a hold does not move the lungs at all.
    ///   - side: Which nostril, taken from `Stage.signedPhases` rather than from
    ///     the phase's own passage, so an exhale is drawn on the side of the
    ///     inhale that filled it and the figure never flips at full lungs.
    ///   - reduceMotion: Suppresses the turn, leaving scale. It does not
    ///     suppress a nostril: a vent and a swell are static asymmetries, so the
    ///     setting costs the figure nothing it was saying about the breath.
    ///   - configuration: Which treatment to draw.
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

    /// Which figure ink a phase is stroked in.
    ///
    /// The technique drawings' four inks rather than a palette of this figure's
    /// own, so the player and the catalogue say the same thing in the same
    /// colour — and so the exhale arrives already carrying the softening
    /// measured to clear WCAG 1.4.11's 3:1 on every goal accent in every
    /// appearance. Nothing here fades a stroke, so there is no second
    /// measurement to keep in step.
    ///
    /// **Those measurements are against `Theme.Surface.ground`.** A screen
    /// wearing `accentGround(_:)` — the session player — carries two legible
    /// marks where a figure needs four, so it puts the ground back underneath
    /// the drawing with `figureGround(across:)` before stroking anything here.
    /// The numbers, and the test that holds them, are in `ThemeColorTests`.
    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
