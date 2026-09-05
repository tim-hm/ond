import OndKit
import OndUI
import SwiftUI

/// The mapping from a session's timeline onto one frame of the breathing
/// shape — `OndUI` owns what the glyph *is*, this file owns where a breath
/// puts it. The `BreathFigurePose` split, for the same reason.
public extension BreathGlyph.Pose {
    /// The hold tint starts at the phase boundary, never before the hold instruction.
    static let holdCrossfade = Duration.milliseconds(800)

    /// The breath at one instant — a pure function of the frozen clock, so
    /// pause freezes the drawing for free. Scales ride the timeline's fullness
    /// envelope, not the phase kind: the sigh's second sip starts nine tenths
    /// full, so ".inhale means grow from empty" would break stacked breaths.
    /// The haptic swell shares the envelope — do not swap the curve alone.
    init(timeline: SessionTimeline, elapsed: Duration) {
        guard let beat = timeline.beat(at: elapsed) else {
            self = .rest
            return
        }

        let level = SessionTimeline.Beat.level(ofFullness: beat.lungFullness(at: elapsed))
        self.init(
            level: level,
            holdPresence: Self.holdPresence(near: beat, in: timeline, at: elapsed)
        )
    }

    /// The breath at rest, for Home's orb: Coherent Breathing's pace on
    /// `AmbientBreath`'s clock, travelling most of the way from rest to full
    /// — a breath somebody could fall into, not a stir — and never holding.
    static func resting(at time: TimeInterval) -> BreathGlyph.Pose {
        let fullness = AmbientBreath.fullness(at: time, cycle: AmbientBreath.restingCycle)
        return BreathGlyph.Pose(level: 0.25 + 0.60 * fullness, holdPresence: 0)
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

        return BreathGlyph.Pose(level: level, holdPresence: held(breath, isPaused: isPaused))
    }

    /// The pose behind a sweeping ring: the breath parked at the top of its
    /// travel, so the ring alone carries the phase. The Dynamic Island draws
    /// this — at 14 to 22 points a scaling core moves two or three pixels
    /// across a whole inhale, under the size where that reads as motion at
    /// all. The hold's colour still arrives, because colour is not travel.
    static func sweeping(for presence: SessionPresence) -> BreathGlyph.Pose {
        sweeping(breath: presence.breath, isPaused: presence.isPaused)
    }

    /// The sweeping pose's arithmetic, on the two facts it reads — internal
    /// for the same reason `pushed(breath:isPaused:)` is.
    internal static func sweeping(breath: Breath, isPaused: Bool) -> BreathGlyph.Pose {
        BreathGlyph.Pose(level: 1, holdPresence: held(breath, isPaused: isPaused))
    }

    /// The same parked breath for a surface with a clock of its own — the
    /// wrist under Reduce Motion. It parks where the pushed surfaces park, so
    /// the shared component sweeps alike everywhere; the phone session is §6's
    /// derivative and parks in its own envelope. The hold arrives over the
    /// timeline's crossfade, which only a surface with a clock can measure.
    static func sweeping(
        timeline: SessionTimeline,
        elapsed: Duration,
        level: Double = 1
    ) -> BreathGlyph.Pose {
        let hold = timeline.beat(at: elapsed).map {
            holdPresence(near: $0, in: timeline, at: elapsed)
        }

        return BreathGlyph.Pose(level: level, holdPresence: hold ?? 0)
    }

    /// Whether a pushed frame is a hold on screen. Whole numbers only: an
    /// extension steps between snapshots, so there is no clock here to
    /// crossfade against.
    private static func held(_ breath: Breath, isPaused: Bool) -> Double {
        breath.kind.isHold && !isPaused ? 1 : 0
    }

    /// The spec's motion table, driven off one number: the pose walked from
    /// the glyph's own `rest` endpoint to its `full` one by the breath's
    /// level, so retuning an endpoint moves this mapping with it.
    private init(level: Double, holdPresence: Double) {
        func walk(_ field: KeyPath<BreathGlyph.Pose, Double>) -> Double {
            let rest = BreathGlyph.Pose.rest[keyPath: field]
            return rest + (BreathGlyph.Pose.full[keyPath: field] - rest) * level
        }

        self.init(
            coreScale: walk(\.coreScale),
            coreOpacity: walk(\.coreOpacity),
            ringScale: walk(\.ringScale),
            holdPresence: holdPresence
        )
    }

    /// Open holds freeze the plan clock, so their tint must arrive at the boundary.
    static func holdPresence(
        near beat: SessionTimeline.Beat,
        in _: SessionTimeline,
        at elapsed: Duration
    ) -> Double {
        guard beat.kind.isHold, elapsed >= beat.start else { return 0 }
        if beat.isOpenEnded || beat.id == 0 {
            return 1
        }
        let rise = min(holdCrossfade, beat.duration / 2)
        guard rise > .zero else { return 1 }
        return min(1, max(0, (elapsed - beat.start) / rise))
    }
}
