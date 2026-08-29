import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The thing you breathe with, filling the face: the shared breath geometry
/// at wrist size, every layer but the outermost ring, which a 132-point frame
/// has no room for. Over it, the session's own arc. Under Reduce Motion the
/// breath parks at the top of its travel and a phase-filling ring is wound
/// around it — scaling is what that setting stops, not the shape itself.
struct BreathRing: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// The whole plan, not just the beat: the session arc fills once over the
    /// whole of it, which only the timeline can measure.
    let timeline: SessionTimeline
    let accent: Color
    /// The square the breath draws in, resolved by the caller once per layout
    /// rather than here every frame.
    let side: CGFloat

    /// The glyph's frame at full size — fixed rather than the face's width, so
    /// the breath reads at one scale on every case size and the words below it
    /// keep their room. A case too short for both gives the breath back first:
    /// the words are the part that has to be read.
    static let designSide: CGFloat = 132

    /// The smallest frame the breath is drawn at, whatever the face has left.
    /// Below half the design size the core is a dot rather than a shape, and a
    /// breath that has vanished is worse than one the words crowd: the guide
    /// stops giving room back here and lets them overlap it instead.
    static let leastSide: CGFloat = designSide / 2

    /// Where the session arc sits, as a fraction of the frame — §3's 96 points
    /// on the 132-point face. A fraction so it follows the glyph down on a
    /// case that cannot hold the whole of it. It cannot be read off the glyph:
    /// the rings under it breathe between 0.62 and 1.06 of their size, so no
    /// ring holds still long enough for a static mark to ride it.
    private static let arcRatio = 96.0 / 132

    /// The phase ring's stroke. A fixed weight rather than a fraction of the
    /// frame: on the case that gives the breath room back, the ring is what
    /// still has to be read across a room.
    private static let phaseLineWidth: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BreathGlyph(side: side, pose: pose, layers: .card)

            SessionArc(fraction: timeline.progress(at: elapsed))
                .frame(width: side * Self.arcRatio, height: side * Self.arcRatio)

            if reduceMotion {
                phaseRing
                    .animation(.easeInOut(duration: 0.4), value: isStill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The breath at this instant — travelling on the session's clock, or
    /// parked while the ring around it carries the phase. Both mappings are
    /// `OndStyle`'s, so the wrist parks where the Dynamic Island parks.
    private var pose: BreathGlyph.Pose {
        reduceMotion
            ? .sweeping(timeline: timeline, elapsed: elapsed)
            : BreathGlyph.Pose(timeline: timeline, elapsed: elapsed)
    }

    /// The current phase, drawn by the same `PhaseArc` as the phone's Sweeping
    /// guide, so the two devices cannot drift apart. Trimmed by how far through
    /// the beat, not how full the lungs are: fullness does not move during a
    /// hold, so a ring driven by it would sit dead for the phase.
    private var phaseRing: some View {
        PhaseArc(
            fraction: beat?.fraction(at: elapsed) ?? 0,
            tint: tint,
            lineWidth: Self.phaseLineWidth
        )
        .frame(width: side, height: side)
    }

    /// The hold's indigo while the breath is held, the goal's accent while it
    /// moves — for the phase ring, whose whole guide is one stroke. The glyph
    /// does not read this: its core crossfades to the hold's own indigo on the
    /// phase clock, and the goal never reaches the breath.
    private var tint: Color {
        isStill ? Theme.Breath.hold : accent
    }

    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }
}
