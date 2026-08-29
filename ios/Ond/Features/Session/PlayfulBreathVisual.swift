import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The breath guide a small child follows: a flower to smell, a candle to
/// blow out. It stands in for `BreathVisual`'s sphere and nothing else — the
/// ring, ground, tint rules and Reduce Motion fallback are the sphere's. The
/// flame scales by the breath's *level*, not `lungFullness`: fullness bottoms
/// out at `emptyLungs`, which would leave a candle burning after every blow.
struct PlayfulBreathVisual: View {
    /// What the breath is doing, or nil before the first beat.
    let kind: PhaseKind?
    /// How full the lungs are on the bare 0...1 scale. Handed over rather
    /// than re-derived from a beat: `BreathVisual` has already asked that
    /// question to scale its own sphere, and two answers is how two drawings
    /// of one breath come to disagree. The flower and the flame both read it.
    let level: Double
    let tint: Color

    /// How much room the drawing has; every length below is a fraction of it.
    /// Handed over rather than read off `BreathVisual.extent`, which is the
    /// size before Dynamic Type shrinks the guide — a flower drawn to the
    /// design extent inside a smaller frame would spill past the session ring.
    let extent: CGFloat

    /// How far the flower's gradient reaches: the padded radius the drawing
    /// occupies. The subtraction matters — this guide is padded by
    /// `Theme.Spacing.close` inside `BreathVisual`'s frame, and a gradient
    /// stopped at the unpadded radius would clip into a hard edge line.
    private static func bodyReach(within side: CGFloat) -> CGFloat {
        side / 2 - Theme.Spacing.close
    }

    /// Whether the flower is the shape on screen. A hold keeps whichever it was
    /// holding, which is what makes the swap read as a breath rather than as a
    /// slideshow — the flower is what lungs full looks like and the spent candle
    /// is what lungs empty looks like.
    private var showsFlower: Bool {
        switch kind {
        case .inhale, .holdIn, nil: true
        case .exhale, .holdOut: false
        }
    }

    var body: some View {
        ZStack {
            flower
                .opacity(showsFlower ? 1 : 0)
            candle
                .opacity(showsFlower ? 0 : 1)
        }
        // The one crossfade, and the only place the two shapes meet. Slower than
        // the tint's 0.4s would suggest is needed, because this swaps the whole
        // drawing rather than recolouring it — under 0.3s it reads as a cut.
        .animation(.easeInOut(duration: 0.45), value: showsFlower)
    }

    /// Opens as the lungs fill: the bud grows *and* its petals separate, so
    /// the top of an inhale is a different shape, not the same one larger —
    /// scale alone is what the sphere already does, and a child watching a
    /// circle grow has been told nothing about flowers.
    private var flower: some View {
        PetalShape(openness: level)
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: tint.opacity(0.92), location: 0),
                        .init(color: tint.opacity(0.7), location: 0.72),
                        .init(color: tint.opacity(0.15), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.bodyReach(within: extent)
                )
            )
            .overlay(heart)
            // A bud at rest is a little over half open, never shut: a flower
            // closed to a point at the bottom of every breath reads as dying.
            .scaleEffect(0.62 + 0.38 * level)
    }

    /// The seed head, which stops the open flower reading as a splash. A
    /// gradient falling to nothing rather than a blurred circle: a blur is
    /// the one thing here that cannot be drawn in the frame's own pass, and
    /// every other soft edge in both apps is already a gradient.
    private var heart: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.55), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: extent * Proportion.heartWidth / 2
                )
            )
            .frame(width: extent * Proportion.heartWidth)
    }

    /// The candle, burning down over the exhale and out at the end of it.
    ///
    /// The wax holds its size throughout, so only the flame moves: a candle that
    /// shrank along with its own flame would be a candle being used up, which is
    /// a different story than the one being told.
    private var candle: some View {
        ZStack {
            glow

            VStack(spacing: 0) {
                flame
                    .frame(
                        width: extent * Proportion.flameWidth,
                        height: extent * Proportion.flameHeight
                    )
                    // Scaled from its foot, so it burns down into the wick
                    // rather than shrinking towards its own middle and floating.
                    .scaleEffect(level, anchor: .bottom)
                    .opacity(level)

                wax
            }
            .frame(height: extent * Proportion.column)
        }
    }

    /// The light the flame throws. A candle is narrow and the flower it
    /// alternates with fills the frame: without the glow the exhale reads as
    /// the picture collapsing rather than as a breath. It fades with the
    /// flame, so the screen dims as the child blows.
    private var glow: some View {
        RadialGradient(
            stops: [
                .init(color: tint.opacity(Ink.glowCore), location: 0),
                .init(color: tint.opacity(Ink.glowEdge), location: 0.55),
                .init(color: tint.opacity(0), location: 1),
            ],
            center: .center,
            startRadius: 0,
            endRadius: extent * Proportion.glowReach
        )
        .opacity(level)
        .offset(y: -extent * Proportion.glowRise)
    }

    /// A flame with a lean on it, tipped further as it goes — the drawing's way
    /// of saying it is being blown rather than merely dimmed.
    private var flame: some View {
        FlameShape()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(Ink.flameTip), tint, tint.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .rotationEffect(.degrees(12 * (1 - level)), anchor: .bottom)
    }

    /// The candle itself: a soft column with a wick, tall and narrow so it reads
    /// as a candle rather than as an egg.
    private var wax: some View {
        ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(tint.opacity(Ink.wax))
                .frame(
                    width: extent * Proportion.waxWidth,
                    height: extent * Proportion.waxHeight
                )

            Capsule()
                .fill(tint.opacity(Ink.wick))
                .frame(
                    width: extent * Proportion.wickWidth,
                    height: extent * Proportion.wickHeight
                )
                // Half its own height, so it straddles the top of the wax rather
                // than sitting on it.
                .offset(y: -extent * Proportion.wickHeight / 2)
        }
    }
}

/// How strongly each part of the drawing is inked. These are the numbers WCAG
/// holds this screen to, not taste: `ThemeColorTests.playAccentCarriesTheCandle`
/// measures the marks at exactly these values, so a nudge for looks fails a
/// test. The flame, wax and wick are marks and answer to WCAG 1.4.11's 3:1;
/// the glow is light, sitting with the session ring's 0.18 track.
private enum Ink {
    /// Both marks clear 3:1 at this strength — 3.6:1 light, 5.4:1 dark. The wax
    /// is the whole drawing once the flame is out, which is where an exhale ends
    /// and where a fainter wax left a child looking at nothing.
    static let wax = 0.78
    static let wick = 0.9
    /// The flame's own top, where its gradient is thinnest — and still a mark,
    /// so still 3:1 (3.2:1 light, 4.8:1 dark). Unlike the sphere's rim, which
    /// falls to nothing because a breath has no edge, a flame has a tip and a
    /// child watching for it should be able to see where it ends.
    static let flameTip = 0.72

    static let glowCore = 0.34
    static let glowEdge = 0.10
}

/// Every length in the drawing, as a fraction of the guide's own extent —
/// gathered because the relations between them are the design: the flame and
/// the wax add up to `column`, and the wick is placed from its own height.
/// Tuned by rendering the sweep, not derived — see `PetalShape.petalDepth`.
private enum Proportion {
    static let flameWidth = 0.26
    static let flameHeight = 0.34
    static let waxWidth = 0.22
    static let waxHeight = 0.46
    static let wickHeight = 0.06
    /// A fraction like the rest, and it has to be: held at four points while the
    /// guide shrinks for large type, the wick keeps its width against a wax that
    /// has narrowed by a third and reads stubby exactly where the drawing is
    /// smallest. Four points at the design extent, which is where it was tuned.
    static let wickWidth = 4.0 / 260
    /// The flame and the wax stacked, with the slack that centres them.
    static let column = flameHeight + waxHeight + 0.06
    static let heartWidth = 0.16
    static let glowReach = 0.42
    /// Lifts the glow onto the flame; without it the light appears to come from
    /// the wax.
    static let glowRise = 0.16
}
