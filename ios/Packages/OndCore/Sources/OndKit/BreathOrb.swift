import Foundation

/// The breathing orb's arithmetic: a dot at empty lungs, one full circle at
/// full lungs, and the tumble of rings every breath passes through on the way
/// between.
///
/// In the package rather than on the view for the reason `DialGeometry` is: the
/// part of this drawing that can be wrong *numerically* — rings that fail to
/// settle back into one circle, a spin that carries on into a hold, a lean that
/// ignores the nostril — cannot be exercised through a render in a test. Here
/// it can. The view keeps the strokes, the colours and the perspective; every
/// number they rest on is below.
///
/// The shape of a breath, in this drawing's terms: fully exhaled is a small
/// solid dot, fully inhaled one circle, and the two halves of a breath are
/// different drawings on purpose. An **inhale is bare rings**: `ringCount`
/// copies of the circle each turn fast about their own axis — a different one
/// every breath, and a genuinely three-dimensional one, x, y and z — with
/// nothing drawn behind them, so the expansion is a tumbling cage and only
/// that. An **exhale is a soft sphere**: the cage hands over to one
/// soft-edged body that simply contracts, the breath leaving as quietly as
/// it arrived loudly.
/// Each inhale turns a **whole number of revolutions**, which is the settling
/// made arithmetic: a full turn about any axis is the identity, so rings that
/// complete their turns as the spin decays have landed exactly back on the
/// single circle, with nothing left to snap into place.
///
/// The spin runs on the inhale's own clock — every window below is a share of
/// its duration, so a long slow inhale tumbles langourously and the sigh's
/// sip is a flourish. It climbs quickly, cruises fast through the middle, and
/// spends the last third braking — cosine-eased at both ends of the brake, so
/// neither its onset nor the stop has a jerk — coming to rest just before the
/// phase does. A hold spins nothing: its rings sit at whole turns already,
/// and the colour shift is the whole of what marks it.
public enum BreathOrb {
    /// How many rings tumble.
    public static let ringCount = 3

    /// The orb's scale at empty lungs — the dot, as a share of the full circle.
    ///
    /// This is a *drawing's* floor, deliberately beneath
    /// `SessionTimeline.Beat.emptyLungs`: that number says lungs at rest still
    /// hold air, and the old orb scaled by it directly, which is why an exhale
    /// never fell below nearly half size. The dot reads as a resting point
    /// rather than as absence because it is solid where the circle is hollow —
    /// the fill, not the size, is what says there is still air in the room.
    public static let dotScale: Double = 0.14

    /// How far the whole cage turns towards the working nostril at full spin,
    /// in degrees.
    static let maxLean: Double = 22

    /// The share of an inhale the spin takes to reach full speed. Short, so
    /// the dot bursts into rings rather than easing awake.
    static let riseWindow: Double = 0.15

    /// Where the brake goes on, as a share of the inhale: the spin cruises at
    /// full speed until here — through the fat middle of the breath — and
    /// spends the remaining third slowing.
    static let fallStart: Double = 2.0 / 3.0

    /// Where the spin has stopped, as a share of the inhale. Just short of the
    /// end, and that margin is load-bearing rather than taste: the hold's
    /// colour crossfade animates whatever the angle's *value* does at the
    /// boundary, so the rings must already be sitting at their whole turns on
    /// the last frame the inhale draws, or the crossfade winds them visibly
    /// backwards.
    static let settled: Double = 0.97

    /// One ring of the tumble: how far it has turned, and the axis it turns
    /// about, as a unit vector in view coordinates.
    public struct Ring: Sendable, Equatable {
        /// Degrees turned from the flat circle, kept in 0..<360. Wrapped here
        /// rather than left to accumulate because the value is *animatable*: a
        /// settled phase reads 0, a hold reads 0, and the crossfade that runs
        /// on the hold boundary (`BreathVisual` animates on `isStill`) finds
        /// nothing to animate. Unwrapped, a two-revolution ring handed 720 → 0
        /// at that boundary spins visibly backwards through both turns — the
        /// same orientation, animated as if it were two turns away.
        public let angle: Double
        public let axisX: Double
        public let axisY: Double
        public let axisZ: Double
    }

    /// Everything the view draws for one instant of the breath.
    public struct Pose: Sendable, Equatable {
        /// The dot's and the interior's scale, `dotScale` at empty lungs to 1
        /// at full.
        public let scale: Double
        /// The rings' own scale, 0 at empty lungs to 1 at full — a floor of
        /// nothing, unlike the dot's. This is what makes the contraction a
        /// collapse rather than a crossfade: below the dot's own size the
        /// rings are inside the ball, and at empty they have vanished into
        /// its centre instead of fading out on its rim.
        public let ringScale: Double
        /// The soft body's opacity — the resting dot, and the sphere an
        /// exhale contracts. 1 through the whole of an exhale whatever the
        /// level; on the way up it has dissolved by level 0.3, once the
        /// rings have taken over.
        public let bodyOpacity: Double
        /// The cage's opacity: 1 wherever the rings show, 0 through an
        /// exhale, which is the sphere alone. The swap lands on a phase
        /// boundary, where the view's crossfade smooths it.
        public let ringOpacity: Double
        /// Degrees of turn about the vertical axis, towards the nostril the
        /// air is moving through. Positive turns the cage towards the viewer's
        /// left, which is where a mirror puts the practitioner's left nostril.
        /// Rides the spin's own envelope, so it rises with the tumble and is
        /// gone before the phase ends — a boundary never snaps it between
        /// sides.
        public let lean: Double
        /// The tumble, `ringCount` strong, coincident wherever the spin rests.
        public let rings: [Ring]
    }

    /// The orb at one instant.
    ///
    /// - Parameters:
    ///   - level: how far up the breath, 0 (empty) to 1 (full) —
    ///     `SessionTimeline.Beat.level(ofFullness:)` re-bases a fullness onto
    ///     it. Drives the size and the dot, never the spin.
    ///   - progress: how far through the current phase, 0...1 —
    ///     `SessionTimeline.Beat.fraction(at:)`. The spin's whole clock, so
    ///     every window above is a share of this phase's own duration.
    ///   - kind: what the breath is doing, or nil before the first beat. Only
    ///     an inhale spins; an exhale swaps the cage for the soft sphere, and
    ///     a hold moves nothing, whatever its progress says.
    ///   - breath: seeds this breath's axes — pass the beat's id, salted with
    ///     any per-session entropy the caller holds, so every breath tumbles
    ///     its own way, no two sessions repeat, and a test that fixes the seed
    ///     can still pin any tumble it likes.
    ///   - side: the nostril the air is moving through, or nil when there is
    ///     no side to lean to.
    public static func pose(
        atLevel level: Double,
        through progress: Double,
        during kind: PhaseKind?,
        breath: Int,
        toward side: Passage.Side?
    ) -> Pose {
        let level = min(max(level, 0), 1)
        let spins = kind == .inhale
        let exhales = kind == .exhale
        let turn = spins ? turn(through: progress) : 0
        let envelope = spins ? envelope(through: progress) : 0

        let rings = (0 ..< ringCount).map { index -> Ring in
            var random = SplitMix(seed: breath, lane: index)
            let axis = random.axis()
            // Eight or twelve revolutions: two speeds, so the rings pass
            // through each other instead of tumbling in formation, and both
            // high enough that the cruise reads as a fast spin — several
            // turns a second on an ordinary inhale — rather than a drift.
            let revolutions = Double(8 + 4 * random.coin())
            return Ring(
                angle: (360 * revolutions * turn).truncatingRemainder(dividingBy: 360),
                axisX: axis.x,
                axisY: axis.y,
                axisZ: axis.z
            )
        }

        return Pose(
            scale: dotScale + (1 - dotScale) * level,
            ringScale: level,
            bodyOpacity: exhales ? 1 : max(0, 1 - level / 0.3),
            ringOpacity: exhales ? 0 : 1,
            lean: (side?.rawValue ?? 0) * maxLean * envelope,
            rings: rings
        )
    }

    /// How much of its revolutions a ring has turned at `progress`: 0 at the
    /// inhale's start, 1 from `settled` onwards, monotonic between.
    ///
    /// The integral of `envelope(through:)` — climb, cruise, brake — with the
    /// ramps cosine-eased so the velocity is not merely continuous but has no
    /// corner: the brake comes on gently at `fallStart` and the deceleration
    /// itself dies away into the stop, which is what "quickly but smoothly"
    /// asks of the arithmetic.
    static func turn(through progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        let rise = riseWindow
        let fall = settled - fallStart
        let distance = rise / 2 + (fallStart - rise) + fall / 2

        if progress < rise {
            return (progress - rise / .pi * sin(.pi * progress / rise)) / 2 / distance
        }
        if progress < fallStart {
            return (rise / 2 + (progress - rise)) / distance
        }
        if progress < settled {
            let braked = progress - fallStart
            let travelled = rise / 2 + (fallStart - rise)
                + (braked + fall / .pi * sin(.pi * braked / fall)) / 2
            return travelled / distance
        }
        return 1
    }

    /// The spin's own loudness at `progress` — the normalised angular velocity
    /// of `turn(through:)`, 0 at both ends of the inhale and 1 on the cruise.
    /// What the lean rides, so it exists exactly while the tumble does.
    static func envelope(through progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)

        if progress < riseWindow {
            return (1 - cos(.pi * progress / riseWindow)) / 2
        }
        if progress < fallStart {
            return 1
        }
        if progress < settled {
            return (1 + cos(.pi * (progress - fallStart) / (settled - fallStart))) / 2
        }
        return 0
    }
}

/// A tiny deterministic generator (SplitMix64), here so a breath's "random"
/// axes are a pure function of the beat that owns them: the same session
/// replays identically, a paused frame re-renders identically, and a test can
/// name the tumble it expects.
private struct SplitMix {
    private var state: UInt64

    init(seed: Int, lane: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
            &+ UInt64(lane &+ 1) &* 0xBF58_476D_1CE4_E5B9
    }

    /// The next value in [-1, 1).
    private mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Double(mixed >> 11) / Double(1 << 52) - 1
    }

    /// Zero or one, evenly.
    mutating func coin() -> Int {
        next() < 0 ? 0 : 1
    }

    /// A unit axis that is random in x, y and z but never degenerate: the
    /// in-plane part is kept dominant, because a circle spun about the pure
    /// z axis is a circle — invisible — and a ring that happened to draw that
    /// axis would sit still through the whole breath.
    mutating func axis() -> UnitAxis {
        let azimuth = next() * .pi
        let z = next() * 0.6
        let planar = (1 - z * z).squareRoot()
        return UnitAxis(x: planar * cos(azimuth), y: planar * sin(azimuth), z: z)
    }
}

/// A direction in view coordinates, unit length by construction.
private struct UnitAxis {
    let x: Double
    let y: Double
    let z: Double
}
