import OndKit
import OndUI
import SwiftUI

/// The thing you watch while you breathe.
///
/// Three renderings of one value, and only ever one on screen. The rings
/// breathe between two resting shapes — a solid dot at empty lungs, one circle
/// at full — through a cage of turning rings whose arithmetic lives in
/// `BreathOrb`; the sphere is the guide that shipped first, a disc scaling
/// with the breath, kept behind `BreathVisualStyle`. Under Reduce Motion both
/// are exactly the motion that causes trouble, so the same progress drives a
/// ring that fills instead, whatever the setting says.
struct BreathVisual: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// How far through the whole session, 0...1 — the outer ring's fill.
    let progress: Double
    let accent: Color
    /// Per-session entropy folded into every breath's tumble seed, so no two
    /// runs of the same exercise spin alike. The screen draws it once at
    /// random and holds it; this view stays a pure function of its inputs.
    let tumbleSalt: Int

    /// How much room the drawing takes, which is also how much ground has to be
    /// restored under it — one number, so the patch cannot be sized against a
    /// figure that has since grown.
    static let extent: CGFloat = 260

    @Environment(SessionSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The session ring's stroke. Thin on purpose: it is reference, not
    /// instruction, and the orb inside it is the thing being followed.
    private static let sessionLineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            sessionRing

            Group {
                if reduceMotion {
                    ring
                } else {
                    switch settings.breathVisual {
                    case .rings: orb
                    case .sphere: sphere
                    }
                }
            }
            // Clear of the ring, so a full inhale tops out just inside it
            // rather than swallowing it.
            .padding(Theme.Spacing.close)
        }
        .frame(width: Self.extent, height: Self.extent)
        .animation(.easeInOut(duration: 0.4), value: isStill)
        // The session ring is the accent at full strength, which measures
        // 2.45:1 against the top of the wash it was sitting on — under the 3:1
        // WCAG 1.4.11 asks of a mark that carries meaning. Restoring the ground
        // is what fixes that, and it is also what would let a stroked breath
        // figure take this slot, since the wash carries two legible marks where
        // a figure needs four. The orb itself was never in danger, being a fill
        // rather than a stroke.
        .figureGround()
    }

    /// How far through the session, as quiet chrome at the edge — the wrist's
    /// treatment, brought back to the phone.
    ///
    /// Kept under Reduce Motion. A ring that fills over ten minutes is not
    /// motion in the sense that setting exists to suppress; it is the same
    /// number the progress bar used to carry, in a place that costs no layout.
    private var sessionRing: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: Self.sessionLineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: Self.sessionLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }

    /// Slate blue while the breath is held, the goal's accent while it moves.
    ///
    /// The same shift the marketing site's orb makes, and the reason it is worth
    /// making here: a hold is the one phase where nothing is scaling, so with
    /// haptics and audio off the colour is all that marks the change.
    private var tint: Color {
        isStill ? Theme.Accent.still : accent
    }

    /// Whether the breath is being held. The animation keys off this rather than
    /// off `tint`, so the crossfade runs on the two boundaries that change the
    /// colour instead of on all four.
    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }

    /// A ring's stroke. Heavier than the session ring's because three of these
    /// coincide at full lungs, and the stack is what draws the single circle
    /// the inhale settles onto.
    private static let ringLineWidth: CGFloat = 2

    /// How much depth the tilts get. Well short of SwiftUI's default of 1,
    /// which is a wide-angle lens: the cage should read as turning, not as
    /// rushing at the screen.
    private static let ringPerspective: CGFloat = 0.3

    private var orb: some View {
        let pose = BreathOrb.pose(
            atLevel: SessionTimeline.Beat.level(ofFullness: fullness),
            through: beat?.fraction(at: elapsed) ?? 0,
            still: isStill,
            breath: (beat?.id ?? 0) &+ tumbleSalt,
            toward: beat?.passage?.side
        )

        return ZStack {
            // The interior, so the cage reads as a body rather than wire.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.4), tint.opacity(0.04)],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.extent / 2
                    )
                )
                .scaleEffect(pose.scale)

            // Scaled to `ringScale`, not `scale`: the rings' floor is the
            // centre, the dot's is its own face, and the gap between the two
            // is what lets a contraction end with the rings collapsing into
            // the ball instead of fading out on its rim.
            ForEach(pose.rings.indices, id: \.self) { index in
                let ring = pose.rings[index]
                Circle()
                    // Full strength, not a softened wash: the ring is the
                    // guide, so it answers WCAG 1.4.11's 3:1 against the
                    // ground `figureGround()` restores — which the accents
                    // clear at full strength and five of them fail at 0.7.
                    .stroke(tint, lineWidth: Self.ringLineWidth)
                    .rotation3DEffect(
                        .degrees(ring.angle),
                        axis: (x: ring.axisX, y: ring.axisY, z: ring.axisZ),
                        perspective: Self.ringPerspective
                    )
                    .scaleEffect(pose.ringScale)
            }

            // The exhaled dot, dissolving as the rings take over.
            Circle()
                .fill(tint)
                .opacity(pose.coreOpacity)
                .scaleEffect(pose.scale)
        }
        .rotation3DEffect(
            .degrees(pose.lean),
            axis: (x: 0, y: 1, z: 0),
            perspective: Self.ringPerspective
        )
    }

    /// The original guide, kept selectable: one soft disc, scaled by the
    /// shared fullness rather than re-based onto the rings' wider range.
    private var sphere: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.85), tint.opacity(0.25)],
                    center: .center,
                    startRadius: 4,
                    endRadius: Self.extent / 2
                )
            )
            .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 1))
            .scaleEffect(fullness)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: beat?.fraction(at: elapsed) ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(24)
    }

    /// How full the lungs are, on the shared fullness scale `BreathOrb`
    /// re-bases. Empty before the first beat, which is where a breath starts
    /// from.
    private var fullness: Double {
        beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
    }
}
