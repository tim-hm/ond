import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The thing you breathe with, filling the face.
///
/// The shared breath geometry at wrist size — every layer but the outermost
/// ring, which a 132-point frame has no room for. Under Reduce Motion the
/// glyph gives way to a ring that fills with the phase — the scaling is
/// exactly the effect that setting exists to stop, and a glyph merely frozen
/// would leave the wrist with nothing to follow.
///
/// Both layers here belong to the breath alone: the whole-session number is
/// the header's remaining time, and nothing on this face may take it back.
struct BreathRing: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// The whole plan, not just the beat: the glyph's hold ring crossfades
    /// across phase boundaries, which only the timeline can see.
    let timeline: SessionTimeline
    let accent: Color

    /// The glyph's frame — fixed rather than the face's width, so the breath
    /// reads at one scale on every case size and the words below it keep
    /// their room on the smallest.
    static let side: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                phaseRing
                    .animation(.easeInOut(duration: 0.4), value: isStill)
            } else {
                BreathGlyph(
                    side: Self.side,
                    pose: BreathGlyph.Pose(timeline: timeline, elapsed: elapsed),
                    layers: .watch
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The current phase, drawn by the same `PhaseArc` as the phone's Reduce
    /// Motion guide, so the two devices cannot drift apart.
    ///
    /// Trimmed by how far through the beat we are rather than by how full the
    /// lungs are. A hold is what proves the difference: fullness does not move
    /// during one, so a ring driven by it would sit dead for the length of the
    /// phase — which is the state this replaced.
    private var phaseRing: some View {
        PhaseArc(fraction: beat?.fraction(at: elapsed) ?? 0, tint: tint, lineWidth: 8)
            .frame(width: Self.side, height: Self.side)
    }

    /// The hold's indigo while the breath is held, the goal's accent while it
    /// moves — for the arc, which marks a hold with colour alone. The glyph
    /// does not read this: its hold ring is the phase colour on every session.
    private var tint: Color {
        isStill ? Theme.Breath.hold : accent
    }

    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }
}
