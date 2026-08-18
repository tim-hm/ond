import OndKit
import OndUI
import SwiftUI

/// The mapping from a session's timeline onto one frame of the breathing
/// shape — `OndUI` owns what the glyph *is*, this file owns where a breath
/// puts it. The `BreathFigurePose` split, for the same reason.
public extension BreathGlyph.Pose {
    /// How long the hold ring's crossfade takes, straddling the phase
    /// boundary: it starts fading in before the hold begins and finishes
    /// after, so the hold reads as the breath arriving at the top rather than
    /// as an element being added. Linear, deliberately — an eased fade over
    /// eight tenths of a second reads as a flicker.
    static let holdCrossfade = Duration.milliseconds(800)

    /// The breath at one instant of a session — a pure function of the frozen
    /// clock, which is what makes pause freeze the drawing for free.
    ///
    /// The scales ride the timeline's own fullness envelope through
    /// `Beat.level(ofFullness:)` rather than being derived from the phase
    /// kind. That is a load-bearing choice, not a shortcut: `startFullness`
    /// and `endFullness` are laid out across the whole plan, so the
    /// physiological sigh's second sip starts nine tenths full and climbs the
    /// last tenth — a mapping from `.inhale` to "grow from empty" would
    /// break every stacked breath. The smoothstep inside `lungFullness` is
    /// this app's realisation of the refresh spec's `cubic-bezier(0.42, 0,
    /// 0.40, 1)`: both are S-curves with zero end slope, within two percent
    /// of each other everywhere, and swapping the curve would ripple into
    /// the haptic swell that shares the envelope.
    init(timeline: SessionTimeline, elapsed: Duration) {
        guard let beat = timeline.beat(at: elapsed) else {
            self = .rest
            return
        }

        let level = SessionTimeline.Beat.level(ofFullness: beat.lungFullness(at: elapsed))
        self.init(
            level: level,
            holdRing: Self.holdPresence(in: timeline, around: beat, at: elapsed)
        )
    }

    /// The idle breath for a surface alive without a session — the Home card.
    /// Rides `AmbientBreath`, the module's one free-running clock, mapped
    /// into a narrow band so a resting card stirs rather than breathes.
    static func idle(at time: TimeInterval) -> BreathGlyph.Pose {
        BreathGlyph.Pose(
            level: 0.25 + 0.35 * AmbientBreath.fullness(at: time),
            holdRing: 0
        )
    }

    /// The static frame a Live Activity push draws: the current phase's
    /// *target* state, because the extension cannot animate — each push moves
    /// the glyph one step and the system's own timer carries the motion
    /// between pushes.
    static func pushed(for presence: SessionPresence) -> BreathGlyph.Pose {
        pushed(breath: presence.breath, isPaused: presence.isPaused)
    }

    /// The pushed pose's arithmetic, on the two facts it actually reads —
    /// internal so the tests reach it without composing a whole presence.
    internal static func pushed(breath: Breath, isPaused: Bool) -> BreathGlyph.Pose {
        let level: Double = switch breath.kind {
        case .inhale, .holdIn: 1
        case .exhale, .holdOut: 0
        }

        return BreathGlyph.Pose(
            level: level,
            holdRing: breath.kind.isHold && !isPaused ? 1 : 0
        )
    }

    /// The spec's motion table, driven off one number: the pose walked from
    /// the glyph's own `rest` endpoint to its `full` one by the breath's
    /// level, so retuning an endpoint moves this mapping and the hold ring's
    /// waiting scale together.
    private init(level: Double, holdRing: Double) {
        func walk(_ field: KeyPath<BreathGlyph.Pose, Double>) -> Double {
            let rest = BreathGlyph.Pose.rest[keyPath: field]
            return rest + (BreathGlyph.Pose.full[keyPath: field] - rest) * level
        }

        self.init(
            coreScale: walk(\.coreScale),
            coreOpacity: walk(\.coreOpacity),
            ringScale: walk(\.ringScale),
            holdRing: holdRing
        )
    }

    /// The hold ring's presence at `elapsed` — a pure function of the
    /// timeline, not a triggered animation, so scrubbing, pausing and
    /// resuming all land on the right frame with nothing to cancel.
    ///
    /// Each hold contributes a trapezoid: a linear rise straddling its start,
    /// a linear fall straddling its end, clamped so a short hold or a short
    /// neighbour cannot push the ramp past what is actually there. Boundaries
    /// are the beats' absolute edges on purpose — the turn gap shaves the
    /// *breathing* sub-interval, not the boundary instant, and this fade
    /// belongs to the boundary. A timeline with no holds never sums anything,
    /// so the ring simply never appears.
    private static func holdPresence(
        in timeline: SessionTimeline,
        around beat: SessionTimeline.Beat,
        at elapsed: Duration
    ) -> Double {
        // Only the current beat and its neighbours can overlap a crossfade
        // window: the ramps are clamped to at most half a neighbour's span.
        // A plain loop, not a filter/map chain — this runs every frame, and
        // the chain's transient arrays were the pose's whole allocation cost.
        var presence = 0.0
        for index in (beat.id - 1) ... (beat.id + 1) {
            guard let hold = Self.beat(index, in: timeline), hold.kind.isHold else { continue }
            presence = max(presence, ramp(of: hold, in: timeline, at: elapsed))
        }
        return presence
    }

    /// One hold's trapezoid at `elapsed`.
    ///
    /// An open-ended hold completes its fade *at* the boundary rather than
    /// astride it: a retention freezes the plan clock exactly on its start, so
    /// a ramp still rising there would leave the ring half-drawn for the whole
    /// hold. Its fall never comes from the plan either — the release is the
    /// person's, and the frozen clock keeps the ring until they take it.
    ///
    /// A hold with no beat before it arrives complete the same way: the plan
    /// opens already inside it, so there is no boundary to straddle and a
    /// half-drawn ring on the first frame would be the crossfade's midpoint
    /// shown as a state.
    private static func ramp(
        of hold: SessionTimeline.Beat,
        in timeline: SessionTimeline,
        at elapsed: Duration
    ) -> Double {
        let previous = beat(hold.id - 1, in: timeline)
        let next = beat(hold.id + 1, in: timeline)

        let rise = window(hold.duration, beside: previous?.duration)
        let riseStart = hold.isOpenEnded || previous == nil
            ? hold.start - rise
            : hold.start - rise / 2
        // A final or open-ended hold has no scripted boundary to fade across:
        // the ring stays until the session leaves it.
        let fall = hold.isOpenEnded ? nil : next.map { window(hold.duration, beside: $0.duration) }

        let rising = fraction(of: elapsed, from: riseStart, over: rise)
        let falling = fall.map { 1 - fraction(of: elapsed, from: hold.end - $0 / 2, over: $0) } ?? 1

        return max(0, min(rising, falling))
    }

    /// The beat at `index`, or nil off either end of the plan.
    private static func beat(_ index: Int, in timeline: SessionTimeline) -> SessionTimeline.Beat? {
        timeline.beats.indices.contains(index) ? timeline.beats[index] : nil
    }

    /// A crossfade window clamped to what the hold and its neighbour afford:
    /// half of each side's span at most, so the ramp never outlives the beat
    /// it is straddling into.
    private static func window(_ hold: Duration, beside neighbour: Duration?) -> Duration {
        min(holdCrossfade, hold, neighbour ?? hold)
    }

    /// Linear progress of `elapsed` through a window, clamped 0...1.
    private static func fraction(
        of elapsed: Duration,
        from start: Duration,
        over span: Duration
    ) -> Double {
        guard span > .zero else { return elapsed >= start ? 1 : 0 }

        return min(1, max(0, (elapsed - start) / span))
    }
}
