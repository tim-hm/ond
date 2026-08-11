import OndKit
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
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    let tint: Color

    /// Whether the flower is the shape on screen. A hold keeps whichever it was
    /// holding, which is what makes the swap read as a breath rather than as a
    /// slideshow — the flower is what lungs full looks like and the spent candle
    /// is what lungs empty looks like.
    private var showsFlower: Bool {
        switch beat?.kind {
        case .inhale, .holdIn, nil: true
        case .exhale, .holdOut: false
        }
    }

    /// How full the lungs are on the bare 0...1 scale — 1 at the top of a
    /// breath, 0 at the bottom of one. The flower opens along it and the flame
    /// burns down along it, so both read from the same number.
    private var level: Double {
        SessionTimeline.Beat.level(
            ofFullness: beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
        )
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
                    endRadius: BreathVisual.extent / 2 - Theme.Spacing.close
                )
            )
            .overlay(heart)
            // A bud at rest is a little over half open, never shut: a flower
            // closed to a point at the bottom of every breath reads as dying.
            .scaleEffect(0.62 + 0.38 * level)
    }

    /// The seed head, which is what stops the open flower reading as a splash.
    private var heart: some View {
        Circle()
            .fill(tint.opacity(0.55))
            .frame(width: BreathVisual.extent * 0.16)
            .blur(radius: 6)
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
                        width: BreathVisual.extent * 0.26,
                        height: BreathVisual.extent * 0.34
                    )
                    // Scaled from its foot, so it burns down into the wick
                    // rather than shrinking towards its own middle and floating.
                    .scaleEffect(max(level, 0.001), anchor: .bottom)
                    .opacity(level)

                wax
            }
            .frame(height: BreathVisual.extent * 0.86)
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
                .init(color: tint.opacity(0.34), location: 0),
                .init(color: tint.opacity(0.10), location: 0.55),
                .init(color: tint.opacity(0), location: 1),
            ],
            center: .center,
            startRadius: 0,
            endRadius: BreathVisual.extent * 0.42
        )
        .opacity(level)
        // Centred on the flame rather than on the drawing, or the light appears
        // to come from the wax.
        .offset(y: -BreathVisual.extent * 0.16)
    }

    /// A flame with a lean on it, tipped further as it goes — the drawing's way
    /// of saying it is being blown rather than merely dimmed.
    private var flame: some View {
        FlameShape()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.45), tint, tint.opacity(0.9)],
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
                .fill(tint.opacity(0.42))
                .frame(
                    width: BreathVisual.extent * 0.22,
                    height: BreathVisual.extent * 0.46
                )

            Capsule()
                .fill(tint.opacity(0.85))
                .frame(width: 4, height: BreathVisual.extent * 0.06)
                .offset(y: -BreathVisual.extent * 0.025)
        }
    }
}

/// A round bud that becomes a six-petalled flower.
///
/// A polar curve rather than six overlaid ovals: one closed path takes one fill
/// and one gradient, where six shapes would each need their own and would show
/// their seams wherever they crossed. `openness` moves the petal depth only —
/// the radius at a petal's tip is the circle's throughout, so the shape grows
/// into the same bounds the sphere occupied instead of outrunning the ring
/// around it.
private struct PetalShape: Shape {
    /// 0 is a circle; 1 puts the valleys at 56% of the tips.
    ///
    /// Tuned by rendering the sweep rather than by arithmetic: at the 0.30 depth
    /// this started on, a fully open flower read as a starfish — six thin arms
    /// off a small middle. 0.22 is where the petals are still obvious at a glance
    /// and the shape still has a body.
    var openness: Double

    /// Six, because it is the count that still reads as a flower at a glance
    /// while leaving each petal wide enough to survive the blur at the rim.
    private let petals = 6

    /// So the shape interpolates across a phase rather than snapping between
    /// frames — the crossfade would otherwise be the only thing moving.
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let reach = min(rect.width, rect.height) / 2
        let depth = 0.22 * min(max(openness, 0), 1)
        // Enough segments that the curve reads as smooth at 260pt and few enough
        // that rebuilding it every frame stays cheap.
        let segments = 120

        var path = Path()
        for segment in 0 ... segments {
            let angle = Double(segment) / Double(segments) * 2 * .pi
            let radius = reach * (1 - depth + depth * cos(Double(petals) * angle))
            let point = CGPoint(
                x: centre.x + radius * cos(angle),
                y: centre.y + radius * sin(angle)
            )

            if segment == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        return path
    }
}

/// A teardrop with a pointed tip and a round foot — a flame as a child draws
/// one, which is the register this whole screen is in.
private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.midX + width * 0.30, y: rect.minY + height * 0.20),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - height * 0.06),
            control2: CGPoint(x: rect.midX + width * 0.26, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.midX - width * 0.26, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.38),
            control2: CGPoint(x: rect.midX - width * 0.30, y: rect.minY + height * 0.20)
        )
        path.closeSubpath()

        return path
    }
}
