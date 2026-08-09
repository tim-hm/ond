import OndKit
import SwiftUI

/// The breath as a motion language rather than one asset.
///
/// One arrangement — evenly spaced places at a reach from the middle — opening
/// through the inhale, turning slowly through a hold, and closing again through
/// the exhale. The mapping is the whole idea: geometry carries physiology, so the
/// four `PhaseKind`s read apart before colour is consulted.
///
/// | Phase     | Reach         | Turn                     |
/// | :-------- | :------------ | :----------------------- |
/// | `inhale`  | opening       | turning                  |
/// | `holdIn`  | wide, steady  | turning at full reach    |
/// | `exhale`  | closing       | turning                  |
/// | `holdOut` | tight, steady | turning at the seed      |
///
/// Scale is what says which half of the breath you are on, and it says it loudly.
/// The turn is there for one job only: nothing may freeze. A hold drawn as a
/// still shape is indistinguishable from an app that has stopped, and the two
/// holds are told apart by reach — wide against tight — rather than by anything
/// the rotation does. On the default six-sided aperture a phase pivots sixty
/// degrees, which registers as an edge being alive rather than as spinning.
///
/// `Form` is what decides how much of that is visible. The aperture is one
/// outline changing size; the wheel adds marks so the pivot can be seen; the
/// rings pull the arrangement apart into orbiting circles, which separates the
/// phases most and is the most to sit in front of.
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
    /// How far a ring's centre sits from the middle at the top of a breath.
    static let orbit: CGFloat = 0.24
    /// How far apart the rings stay at the bottom of one.
    ///
    /// Not zero, and this is the load-bearing small number in the whole figure.
    /// Rings that coincide exactly are one circle, and one circle cannot show a
    /// rotation — so a hold at empty lungs would be the single motionless state
    /// in a language whose whole premise is that nothing freezes. A residual
    /// orbit is also what makes one arrangement serve both scales: at 260 points
    /// it is a tight knot visibly turning, and at the 22 points a Dynamic Island
    /// cue gets it is under a point across and reads as the dot that cue wants.
    static let orbitFloor: CGFloat = 0.035
    /// A ring's own radius at the top of a breath.
    static let openRadius: CGFloat = 0.19
    /// How much of its own reach the arrangement gives up to sit towards the
    /// breathing nostril under `Bias.lean`.
    ///
    /// A fraction of the reach rather than a distance, because the orbit shrinks
    /// by exactly what the offset spends: a leaning figure occupies the same
    /// square as a centred one. An asymmetry that changed the figure's size would
    /// be saying two things at once, and the size already means how full the
    /// lungs are. It sits at 0.3 rather than higher for the same trade: a
    /// stronger lean is also a tighter huddle, and past about a third the rings
    /// overlap enough that the figure reads as crowded rather than as leaning.
    static let leanFraction: CGFloat = 0.3
    /// How far a place on the far side of the midline tapers under `Bias.swell`.
    ///
    /// The far side shrinks rather than the near side growing, for the same
    /// reason as the lean: the reading is "fuller where the air is going", and
    /// taking it out of the far side is the way to get it without spending room.
    ///
    /// Tuned upwards from the 0.45 the rings wanted, and it is worth knowing why
    /// it did not help much. On orbiting circles the taper shrinks a whole circle
    /// and reads immediately; on a symmetric outline it only pulls a few corners
    /// in, and a hexagon dented on one side still looks mostly like a hexagon.
    /// Every asymmetry in `Bias` is weaker on the quiet forms than on the loud
    /// one, and that is a real cost of the quiet ones rather than a number left
    /// untuned.
    static let swellTaper: CGFloat = 0.6

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
    /// otherwise. The rings say it differently — they always converge to one
    /// circle at the bottom, so the reading "a single thing" is carried by the
    /// orbit closing rather than by the size — which leaves how *small* that
    /// circle gets a free choice, and the two answers look quite different.
    public enum Closure: String, Sendable, CaseIterable {
        /// Down to a seed. Reads as the arrival of a breath rather than the
        /// bottom of one, and it is the geometry an Island cue has room for.
        case dot
        /// Down to the same fraction of full extent the orb stops at, so the
        /// closed figure still looks like lungs holding air.
        case lungs

        /// A ring's radius when the breath is at its emptiest.
        ///
        /// A radius rather than an extent, which is the trap here: at the bottom
        /// of a breath the arrangement still reaches `orbitFloor` past each
        /// ring's own edge, so the orb's floor has to have that taken back off it
        /// or the closed figure comes out wider than the orb's — and, since the
        /// answer then exceeds `openRadius`, with rings that *shrink* as the
        /// breath fills.
        var closedRadius: CGFloat {
            switch self {
            case .dot: 0.06
            case .lungs: CGFloat(SessionTimeline.Beat.emptyLungs)
                * (BreathFigure.openRadius + BreathFigure.orbit) - BreathFigure.orbitFloor
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
    /// extent-neutral: a nostril must not resize the figure, because size already
    /// means how full the lungs are.
    ///
    /// All of them vanish as the breath empties, because all of them scale with
    /// bloom. That is what keeps the seed symmetric — the dot an Island cue draws
    /// is the same dot whichever nostril the next inhale goes through.
    public enum Bias: String, Sendable, CaseIterable {
        /// No asymmetry. What every technique breathing through the nose or the
        /// mouth draws.
        case centred
        /// The arrangement huddles towards the breathing side, giving up orbit
        /// for offset. The weakest of the three on its own, because a translation
        /// only reads against a reference — on screen that reference is the frame
        /// the figure is centred in, which a figure seen in isolation does not
        /// have.
        case lean
        /// Rings on the far side taper, so the figure looks fuller where the air
        /// is going. Reads without a reference, which is what a translation
        /// cannot do.
        case swell
        /// The arrangement turns towards the breathing side: the top of the wheel
        /// travels left for the left nostril and right for the right. The
        /// strongest read of the three and the only one that costs no geometry at
        /// all — and the only one that has to be learnt rather than seen, since
        /// nothing on screen says which way is which.
        case spin
    }

    /// What the arrangement is actually drawn as.
    ///
    /// One arrangement, three readings of it. Every form takes its places from
    /// the same angles, at the same reach, bent the same way by a nostril — so
    /// switching between them changes how busy the figure is and nothing about
    /// what it means.
    public enum Form: String, Sendable, CaseIterable {
        /// An iris: one closed outline that opens through the inhale and closes
        /// through the exhale, pivoting slowly as it goes.
        ///
        /// The quiet reading, and the one to judge the language on. A single
        /// outline changing size is the least a figure can do and still say
        /// everything the four phases need said — and the pivot is small enough
        /// on a six-sided aperture that it registers as the edge being alive
        /// rather than as rotation.
        case aperture
        /// A rim carrying the breath, with marks on it carrying the turn.
        ///
        /// Between the other two: the circle is as calm as the aperture, and the
        /// marks make the pivot legible where a symmetric outline hides it.
        case wheel
        /// Circles orbiting one another, blooming out of a dot and collapsing
        /// back into it.
        ///
        /// The elaborate reading. Kept because it is what makes the quiet ones
        /// legible as a choice rather than as the only thing tried, and because
        /// it is the one that unmistakably separates all four phases — at the
        /// price of being a lot of movement to sit in front of for ten minutes.
        case rings
    }

    /// The knobs a treatment is chosen with. Present because this is a prototype
    /// and the choices below are the ones worth seeing side by side, not because
    /// a shipping figure should be configurable.
    ///
    /// The defaults are the quiet end of every one of them: an aperture, one
    /// symmetry step per phase, closing to a dot. What ships would be a decision
    /// here rather than a picker.
    public struct Configuration: Sendable, Equatable {
        /// How many places the arrangement has — blades on the aperture, marks on
        /// the wheel, circles in the rings.
        ///
        /// Six is a compromise the forms pull opposite ways on: an aperture wants
        /// enough sides to read as an opening rather than as a triangle, and it
        /// also wants a small pivot, which is what more sides buy — a phase turns
        /// one symmetry step, so six sides pivot 60° where three pivot 120°. The
        /// rings want fewer, because six circles orbiting is a crowd.
        ///
        /// Clamped where it is written rather than only where it is first set:
        /// this is a `var` a picker binds straight to, so an initialiser's guard
        /// is one the next mutation walks past — and the arrangement builds a
        /// range from it, which traps rather than degrades.
        public var ringCount: Int {
            didSet { ringCount = max(ringCount, 1) }
        }

        public var form: Form
        public var closure: Closure
        public var cadence: Cadence
        public var bias: Bias

        public init(
            ringCount: Int = 6,
            form: Form = .aperture,
            closure: Closure = .dot,
            cadence: Cadence = .even,
            bias: Bias = .swell
        ) {
            self.ringCount = max(ringCount, 1)
            self.form = form
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
    ///     rather than a curve of this figure's own, so the rings and the shipped
    ///     orb are driven by one easing and cannot disagree about when the top of
    ///     a breath is.
    ///   - progress: How far through the phase, 0...1 —
    ///     `SessionTimeline.Beat.fraction`. Drives the turn, which is why it is
    ///     needed alongside `fullness`: a hold does not move the lungs at all.
    ///   - side: Which nostril, taken from `Stage.signedPhases` rather than from
    ///     the phase's own passage, so an exhale is drawn on the side of the
    ///     inhale that filled it and the line never crosses at full lungs.
    ///   - reduceMotion: Suppresses orbit and spin, leaving scale.
    ///   - configuration: Which treatment to draw.
    public static func pose(
        for breath: Breath,
        fullness: Double,
        progress: Double,
        side: Passage.Side? = nil,
        reduceMotion: Bool = false,
        configuration: Configuration = Configuration()
    ) -> Pose {
        let empty = SessionTimeline.Beat.emptyLungs
        let bloom = clamped((fullness - empty) / (1 - empty))
        let step = 360.0 / Double(configuration.ringCount)
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
            isStilled: reduceMotion,
            configuration: configuration
        )
    }

    /// The figure with no session running: one circle at the bottom of a breath.
    ///
    /// The state the Island cue draws between phases and the state a resting home
    /// screen draws, which is the same state — this is where the miniature and
    /// the full figure meet.
    public static func seed(configuration: Configuration = Configuration()) -> Pose {
        Pose(
            bloom: 0,
            spin: .zero,
            side: nil,
            isStilled: false,
            configuration: configuration
        )
    }

    /// Which figure ink a phase is stroked in.
    ///
    /// The technique drawings' four inks rather than a palette of this figure's
    /// own, so the player and the catalogue say the same thing in the same
    /// colour — and so the exhale arrives already carrying the softening measured
    /// to clear WCAG 1.4.11's 3:1 on every goal accent in every appearance.
    /// Nothing here fades a stroke, so there is no second measurement to keep in
    /// step.
    ///
    /// **Those measurements are against `Theme.Surface.ground`, and the session
    /// player is not on it.** That screen wears `accentGround(_:)` — its own goal
    /// accent washed over the ground at up to `Theme.Wash.strongest` — and every
    /// stroke here fails 3:1 against the top of that gradient: the softened
    /// exhale lands between 2.05:1 and 2.73:1, and even the unsoftened inhale
    /// falls to 2.93:1 on the tightest goal accent in the light appearance. The
    /// figures in the catalogue never met this because they sit on the palette's
    /// own ground, and the shipped orb never met it because a filled gradient is
    /// not a stroke that has to be told from its background.
    ///
    /// So this is a decision the prototype does not make: a stroked figure on the
    /// session player needs either a quieter ground under it or an ink that is
    /// not the accent it is being drawn on. The gallery draws on
    /// `paletteGround()`, where the numbers above hold.
    public static func ink(for kind: PhaseKind) -> TechniqueFigure.Ink {
        switch kind {
        case .inhale: .inhale
        case .exhale: .exhale
        case .holdIn, .holdOut: .hold
        }
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
