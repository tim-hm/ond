import OndKit
import OndStyle
import OndUI
import SwiftUI

struct BreathRing: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
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

    /// The phase ring's stroke. A fixed weight rather than a fraction of the
    /// frame: on the case that gives the breath room back, the ring is what
    /// still has to be read across a room.
    private static let phaseLineWidth: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WatchSettings.self) private var settings

    private var drawsArc: Bool {
        settings.breathVisual.drawn(underReduceMotion: reduceMotion) == .sweeping
    }

    var body: some View {
        ZStack {
            BreathGlyph(side: side, pose: pose, layers: .core)
            Circle()
                .stroke(Theme.Breath.exhale.opacity(0.3), lineWidth: 1)
                .frame(width: side, height: side)

            if drawsArc {
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
        drawsArc
            ? .sweeping(timeline: timeline, elapsed: elapsed, level: 0.5)
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
