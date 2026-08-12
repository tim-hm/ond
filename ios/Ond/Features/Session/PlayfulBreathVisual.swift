import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The breath guide a small child follows: a flower to smell, and a candle to
/// blow out.
///
/// The playful register renames two breaths, and this is the same two facts
/// drawn instead of said — so a child who cannot read the words still knows
/// which way the air goes. It stands in for `BreathVisual`'s sphere and nothing
/// else: the session ring around it, the ground under it, the tint rules and the
/// Reduce Motion fallback are all the sphere's, unchanged.
///
/// **The flame going out is the win, not a failure.** Blowing the candle out is
/// what the child is being asked to do, so the flame is at its tallest as the
/// exhale begins and gone by the end of it, leaving a candle nobody has to
/// interpret. That reading is the whole reason the exhale gets a candle rather
/// than a closing flower, and it is why the flame is scaled by the breath's
/// *level* rather than by `lungFullness`: fullness bottoms out at `emptyLungs`,
/// which would leave a candle still burning at the end of every breath somebody
/// had just blown on.
struct PlayfulBreathVisual: View {
    /// What the breath is doing, or nil before the first beat.
    let kind: PhaseKind?
    /// How full the lungs are on the bare 0...1 scale — 1 at the top of a
    /// breath, 0 at the bottom of one. Handed over rather than re-derived from a
    /// beat, because `BreathVisual` has already asked that question to scale its
    /// own sphere and two answers to it is how two drawings of one breath come
    /// to disagree.
    ///
    /// The flower opens along it and the flame burns down along it, so both read
    /// from the same number.
    let level: Double
    let tint: Color

    /// How much room the drawing has, every length below being a fraction of it.
    ///
    /// Handed over rather than read off `BreathVisual.extent`, which is the size
    /// before Dynamic Type has shrunk the guide to leave the words their room —
    /// a flower still drawn to the design extent inside a frame two thirds of it
    /// would spill past the session ring around it.
    let extent: CGFloat

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

    /// Opens as the lungs fill: the bud grows *and* its petals separate, so the
    /// top of an inhale is unmistakably a different shape rather than the same
    /// one larger.
    ///
    /// Two channels for one number because scale alone is what the sphere
    /// already does, and a child watching a circle grow has been told nothing
    /// about flowers.
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
                    endRadius: BreathVisual.bodyReach(within: extent)
                )
            )
            .overlay(heart)
            // A bud at rest is a little over half open, never shut: a flower
            // closed to a point at the bottom of every breath reads as dying.
            .scaleEffect(0.62 + 0.38 * level)
    }

    /// The seed head, which is what stops the open flower reading as a splash.
    ///
    /// A gradient falling to nothing rather than a blurred circle. The two look
    /// alike and cost differently: a blur is the one thing on this screen that
    /// cannot be drawn in the frame's own pass, and every other soft edge in both
    /// apps — the sphere, the glow below, `figureGround()` — is already a
    /// gradient. No reason for this to be the exception.
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

    /// The light the flame throws, which is most of what the drawing weighs.
    ///
    /// Here because a candle is a narrow object and the flower it alternates with
    /// fills the frame: without it the exhale reads as the picture collapsing
    /// rather than as a breath. It fades with the flame, so the screen dims as
    /// the child blows — the same fact told twice, which is what a guide watched
    /// through half-closed eyes needs.
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

/// How strongly each part of the drawing is inked.
///
/// Named and gathered because these are the numbers WCAG holds this screen to,
/// not taste. `ThemeColorTests.playAccentCarriesTheCandle` measures the marks
/// below at exactly these values, so a nudge for looks fails a test rather than
/// quietly costing a child the picture.
///
/// The split is the one `BreathVisual` already draws between a mark and a track:
/// the flame, the wax and the wick carry the meaning and answer to WCAG 1.4.11's
/// 3:1 against the ground `figureGround()` restores; the glow is light rather
/// than a mark and sits with the session ring's 0.18 track, below the bar and
/// carrying nothing that is lost when it goes unseen.
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

/// Every length in the drawing, as a fraction of the guide's own extent.
///
/// Together rather than inline because the relations between them are the design
/// and are invisible one property at a time: the flame and the wax add up to
/// `column`, and the wick is placed from its own height. Tuned by rendering the
/// sweep, not derived — see `PetalShape.petalDepth` for what that caught.
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
