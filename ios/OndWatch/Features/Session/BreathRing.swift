import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The thing you breathe with, filling the face: the shared breath geometry
/// at wrist size, every layer but the outermost ring, which a 132-point frame
/// has no room for. Under Reduce Motion a phase-filling ring replaces the
/// glyph — scaling is exactly what that setting stops, and a frozen glyph
/// would leave nothing to follow. Over it, the session's own arc.
struct BreathRing: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// The whole plan, not just the beat: the session arc fills once over the
    /// whole of it, which only the timeline can measure.
    let timeline: SessionTimeline
    let accent: Color

    /// The glyph's frame — fixed rather than the face's width, so the breath
    /// reads at one scale on every case size and the words below it keep
    /// their room on the smallest.
    static let side: CGFloat = 132

    /// Where the session arc sits — §3's own number for this face. It cannot
    /// be read off the glyph: the rings under it breathe between 0.62 and
    /// 1.06 of their size, so no ring holds still long enough for a static
    /// mark to ride it, and the shared inner ring sits further in besides.
    private static let arcSide: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                phaseRing
                    .animation(.easeInOut(duration: 0.4), value: isStill)
            } else {
                ZStack {
                    BreathGlyph(
                        side: Self.side,
                        pose: BreathGlyph.Pose(timeline: timeline, elapsed: elapsed),
                        layers: .card
                    )
                    sessionArc
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The current phase, drawn by the same `PhaseArc` as the phone's Reduce
    /// Motion guide, so the two devices cannot drift apart. Trimmed by how
    /// far through the beat, not how full the lungs are: fullness does not
    /// move during a hold, so a ring driven by it would sit dead for the
    /// phase — the state this replaced.
    private var phaseRing: some View {
        PhaseArc(fraction: beat?.fraction(at: elapsed) ?? 0, tint: tint, lineWidth: 8)
            .frame(width: Self.side, height: Self.side)
    }

    /// The hold's indigo while the breath is held, the goal's accent while it
    /// moves — for the phase ring, which marks a hold with colour alone. The
    /// glyph does not read this: its core is the phase colour on every session.
    private var tint: Color {
        isStill ? Theme.Breath.hold : accent
    }

    /// The plan, not the phase, which the breathing layers under it already
    /// carry. It draws the number the header spells out.
    private var sessionArc: some View {
        SessionArc(fraction: timeline.progress(at: elapsed))
            .frame(width: Self.arcSide, height: Self.arcSide)
    }

    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }
}
