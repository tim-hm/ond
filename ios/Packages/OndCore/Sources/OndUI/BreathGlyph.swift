import SwiftUI

/// The breathing shape — five concentric layers, drawn once here for every
/// surface that shows a breath: the session screens, the Home card, the lock
/// screen, the Dynamic Island. The app icon is this shape at rest.
///
/// Driven by raw scalars rather than a clock or a beat: the mapping from a
/// session's timeline onto a `Pose` lives in `OndStyle`, which is what keeps
/// this module ignorant of the domain and the drawing identical wherever it
/// appears. Every layer is sized as a ratio of `side`, so one view serves a
/// 300-point session guide and a 26-point Island dot.
///
/// The glows are radial gradients, never `.blur()` — a blur cannot be drawn in
/// the frame's own pass, which is the lesson `PlayfulBreathVisual` already
/// carries.
public struct BreathGlyph: View {
    /// One frame of the breath, as scalars. `Equatable` so an unchanged pose
    /// drops the redraw — the `BreathFigure.Pose` precedent.
    public struct Pose: Equatable, Sendable {
        /// Core and halo scale — `rest` at empty lungs through `full` at the
        /// top, like every field but `holdRing`.
        public var coreScale: Double
        /// Core and halo opacity.
        public var coreOpacity: Double
        /// The two passive rings' scale.
        public var ringScale: Double
        /// The hold ring's presence, 0...1. Opacity only — the ring never
        /// scales; it waits at the top of the breath and the breath arrives.
        public var holdRing: Double

        /// The bottom of the breath — what an idle surface shows. With `full`
        /// below, one of the motion table's two endpoints: they live here,
        /// beside the drawing that waits at them, and `OndStyle` interpolates
        /// between the pair rather than restating their numbers.
        public static let rest = Pose(
            coreScale: 0.5,
            coreOpacity: 0.5,
            ringScale: 0.62,
            holdRing: 0
        )

        /// The top of the breath — the pose the rings' hold mark waits at.
        /// `holdRing` stays zero: its presence is a crossfade of its own, not
        /// part of the breath's travel.
        public static let full = Pose(
            coreScale: 1,
            coreOpacity: 1,
            ringScale: 1.06,
            holdRing: 0
        )

        /// Raw-scalar construction. Ordinary callers take their poses from
        /// the `OndStyle` mappings rather than choosing scalars here; the
        /// fields above say what each one means.
        public init(coreScale: Double, coreOpacity: Double, ringScale: Double, holdRing: Double) {
            self.coreScale = coreScale
            self.coreOpacity = coreOpacity
            self.ringScale = ringScale
            self.holdRing = holdRing
        }
    }

    /// Which of the five layers a surface draws. The core is never dropped;
    /// rings go first as the frame shrinks, the halo holds on to the smallest
    /// glance, and only the compact Island's dot draws the core alone. Below
    /// 12 points the core's gradient collapses to a flat fill on its own.
    public struct Layers: OptionSet, Sendable {
        public let rawValue: Int

        /// `OptionSet` conformance; combine the named layers below rather
        /// than building raw values.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let halo = Layers(rawValue: 1 << 0)
        public static let outerRing = Layers(rawValue: 1 << 1)
        public static let innerRing = Layers(rawValue: 1 << 2)
        public static let holdRing = Layers(rawValue: 1 << 3)
        public static let core = Layers(rawValue: 1 << 4)

        /// The full-screen session guide.
        public static let all: Layers = [.halo, .outerRing, .innerRing, .holdRing, .core]
        /// The watch's session guide — everything but the outermost ring,
        /// which a 132-point frame has no room for.
        public static let watch: Layers = [.halo, .innerRing, .holdRing, .core]
        /// A card or the expanded Island: halo, one ring, the core.
        public static let card: Layers = [.halo, .innerRing, .core]
        /// A glance — the Lock Screen row: halo and core only.
        public static let glance: Layers = [.halo, .core]
    }

    /// How far each layer reaches, as a fraction of the frame.
    private enum Proportion {
        static let outerRing = 0.74
        static let innerRing = 0.50
        static let holdRing = 0.50
        static let core = 0.293
        /// Where the halo's light has fully faded, as a fraction of its radius.
        static let haloFade = 0.66
        /// The core glow's reach past the core's edge — 60pt on the 300pt
        /// session frame.
        static let coreGlow = 0.2
        /// The hold ring's glow reach — 28pt on the session frame.
        static let holdGlow = 0.0933
        /// Where the core's gradient turns fully inhale-coloured.
        static let coreDepth = 0.75
    }

    /// The lit top of the core — vapour, not a token: the same value in both
    /// appearances, because the core is the phase colour everywhere and does
    /// not adapt.
    private static let vapour = Color(red: 0xEA / 255, green: 0xF7 / 255, blue: 0xFA / 255)

    /// Below this core diameter the gradient reads as noise, so the core
    /// becomes a flat fill. No surface asks for a core that small today — the
    /// smallest is the lock screen's 12.9-point glance, sized at 44 points to
    /// clear this line — so the branch is a guard on the next one rather than
    /// a treatment anything currently gets.
    private static let flatFillThreshold: CGFloat = 12

    /// The gradients, built once. Their stops are constants — every location
    /// is a ratio of `Proportion` values, cancelled free of `side` — and
    /// `body` runs at display refresh for the whole of a session, so building
    /// them per frame was the drawing's entire allocation cost.
    private static let haloLight = Gradient(stops: [
        .init(color: Theme.Breath.inhale.opacity(0.3), location: 0),
        .init(color: Theme.Breath.inhale.opacity(0), location: Proportion.haloFade),
    ])

    private static let holdGlowLight: Gradient = {
        let diameter = Proportion.holdRing * Pose.full.ringScale
        let edge = diameter / (diameter + 2 * Proportion.holdGlow)
        return Gradient(stops: [
            .init(color: Theme.Breath.hold.opacity(0), location: max(0, edge - 0.25)),
            .init(color: Theme.Breath.hold.opacity(0.35), location: edge),
            .init(color: Theme.Breath.hold.opacity(0), location: 1),
        ])
    }()

    /// The core glow for the un-overridden diameter, which is every current
    /// surface; an override moves the edge, so its glow is built per call.
    private static let standardCoreGlow = coreGlow(
        edge: Proportion.core / (Proportion.core + 2 * Proportion.coreGlow)
    )

    private static func coreGlow(edge: Double) -> Gradient {
        Gradient(stops: [
            .init(color: Theme.Breath.inhale.opacity(0.5), location: edge),
            .init(color: Theme.Breath.inhale.opacity(0), location: 1),
        ])
    }

    private static let coreBody = Gradient(stops: [
        .init(color: vapour, location: 0),
        .init(color: Theme.Breath.inhale, location: Proportion.coreDepth),
        .init(color: Theme.Breath.inhale, location: 1),
    ])

    let side: CGFloat
    let pose: Pose
    let layers: Layers

    /// - Parameters:
    ///   - side: the square frame this draws in; every layer is a ratio of it.
    ///   - pose: the breath at this instant.
    ///   - layers: which layers this surface affords.
    public init(
        side: CGFloat,
        pose: Pose,
        layers: Layers = .all
    ) {
        self.side = side
        self.pose = pose
        self.layers = layers
    }

    public var body: some View {
        ZStack {
            if layers.contains(.halo) {
                halo
            }
            if layers.contains(.outerRing) {
                ring(Proportion.outerRing, stroke: Theme.Breath.exhale.opacity(0.14), width: 1)
            }
            if layers.contains(.innerRing) {
                ring(Proportion.innerRing, stroke: Theme.Breath.inhale.opacity(0.42), width: 1)
            }
            if layers.contains(.holdRing) {
                holdRing
            }
            if layers.contains(.core) {
                core
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The ambient light behind everything: the inhale's colour, fully faded
    /// by two thirds of the way out. Breathes with the core.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Self.haloLight,
                    center: .center,
                    startRadius: 0,
                    endRadius: side / 2
                )
            )
            .scaleEffect(pose.coreScale)
            .opacity(pose.coreOpacity)
    }

    /// One passive ring, breathing with the pair's shared scale.
    private func ring(_ proportion: Double, stroke: Color, width: CGFloat) -> some View {
        Circle()
            .stroke(stroke, lineWidth: width)
            .frame(width: side * proportion, height: side * proportion)
            .scaleEffect(pose.ringScale)
    }

    /// The hold's mark: a solid indigo ring with a soft annular glow, waiting
    /// at the scale the breathing rings arrive at. Only its opacity ever
    /// moves — the crossfade is the breath reaching the top, not an element
    /// appearing.
    private var holdRing: some View {
        let diameter = side * Proportion.holdRing * Pose.full.ringScale
        let glow = side * Proportion.holdGlow
        let field = diameter + 2 * glow

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Self.holdGlowLight,
                        center: .center,
                        startRadius: 0,
                        endRadius: field / 2
                    )
                )
                .frame(width: field, height: field)
            Circle()
                .stroke(Theme.Breath.hold, lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
        }
        .opacity(pose.holdRing)
    }

    /// The core: lit vapour falling to the inhale's colour, its gradient
    /// origin pulled above centre so the disc reads as a body catching light
    /// rather than a flat dot — keep the off-centre origin. Below the
    /// threshold the whole treatment collapses to a flat fill, which is all a
    /// dot that size can carry.
    private var core: some View {
        let diameter = side * Proportion.core
        let glow = side * Proportion.coreGlow
        let field = diameter + 2 * glow

        return ZStack {
            if diameter >= Self.flatFillThreshold {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Self.standardCoreGlow,
                            center: .center,
                            startRadius: 0,
                            endRadius: field / 2
                        )
                    )
                    .frame(width: field, height: field)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Self.coreBody,
                            center: UnitPoint(x: 0.5, y: 0.32),
                            startRadius: 0,
                            endRadius: diameter / 2
                        )
                    )
                    .frame(width: diameter, height: diameter)
            } else {
                Circle()
                    .fill(Theme.Breath.inhale)
                    .frame(width: diameter, height: diameter)
            }
        }
        .scaleEffect(pose.coreScale)
        // The flat fill keeps full opacity: at that size the breath's fade
        // reads as an empty region rather than empty lungs, so the scale
        // alone carries the travel.
        .opacity(diameter >= Self.flatFillThreshold ? pose.coreOpacity : 1)
    }
}
