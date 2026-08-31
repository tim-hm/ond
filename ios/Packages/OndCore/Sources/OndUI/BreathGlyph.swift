import SwiftUI

/// The breathing shape — four concentric layers, drawn once here for every
/// surface that shows a breath; the app icon is this shape at rest. Driven by
/// raw scalars: the timeline-to-`Pose` mapping lives in `OndStyle`, keeping
/// this module ignorant of the domain. The glows are radial gradients, never
/// `.blur()` — a blur cannot be drawn in the frame's own pass; see `PlayfulBreathVisual`.
public struct BreathGlyph: View {
    /// One frame of the breath, as scalars. `Equatable` so an unchanged pose
    /// drops the redraw — the `BreathFigure.Pose` precedent.
    public struct Pose: Equatable, Sendable {
        /// Core and halo scale — `rest` at empty lungs through `full` at the
        /// top, like every field but `holdPresence`.
        public var coreScale: Double
        /// Core and halo opacity.
        public var coreOpacity: Double
        /// The two passive rings' scale.
        public var ringScale: Double
        /// How present the hold is, 0...1 — its own crossfade, straddling
        /// the phase boundary. The core wears the hold's colour by it, and it
        /// rides the pose so hand and wrist arrive at a hold on one number.
        public var holdPresence: Double

        /// The bottom of the breath — what an idle surface shows. With `full`
        /// below, one of the motion table's two endpoints: they live here,
        /// beside the drawing that waits at them, and `OndStyle` interpolates
        /// between the pair rather than restating their numbers.
        public static let rest = Pose(
            coreScale: 0.5,
            coreOpacity: 0.5,
            ringScale: 0.62,
            holdPresence: 0
        )

        /// The top of the breath — the pose a hold waits at. `holdPresence`
        /// stays zero: the hold's crossfade is its own, not part of the
        /// breath's travel.
        public static let full = Pose(
            coreScale: 1,
            coreOpacity: 1,
            ringScale: 1.06,
            holdPresence: 0
        )

        /// Raw-scalar construction. Ordinary callers take their poses from
        /// the `OndStyle` mappings rather than choosing scalars here; the
        /// fields above say what each one means.
        public init(
            coreScale: Double,
            coreOpacity: Double,
            ringScale: Double,
            holdPresence: Double
        ) {
            self.coreScale = coreScale
            self.coreOpacity = coreOpacity
            self.ringScale = ringScale
            self.holdPresence = holdPresence
        }
    }

    /// Which of the four layers a surface draws. The core is never dropped;
    /// rings go first as the frame shrinks, and the halo holds on to the
    /// smallest glance. Below 12 points the core's gradient collapses to a flat
    /// fill on its own, whichever layers are asked for.
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
        public static let core = Layers(rawValue: 1 << 3)

        /// A card, the expanded Island, or the wrist: halo, one ring, the
        /// core. Everything but the outermost ring, which none of those
        /// frames has the room for.
        public static let card: Layers = [.halo, .innerRing, .core]
        /// A glance — the Lock Screen row: halo and core only.
        public static let glance: Layers = [.halo, .core]
    }

    /// How loudly a surface paints each layer, and how far the core's glow
    /// reaches. A closed set of named values, not free numbers: each one
    /// builds its gradients once, and `body` runs at display refresh for the
    /// whole of a session, so a strength assembled per frame would put the
    /// allocation back that the shared gradients took out.
    public struct Strength: Sendable {
        /// The shared component's own values — what §3 prints.
        public static let standard = Strength()

        /// Home at rest: quieter than a session, over a wider glow on a core
        /// that is the only lit thing on the screen.
        public static let home = Strength(
            halo: 0.24,
            outerRing: 0.13,
            coreGlow: 0.42,
            coreGlowReach: 54.0 / 70
        )

        let halo: Gradient
        let outerRing: Color
        let innerRing: Color
        let core: CoreGlow

        /// Alphas in, paint out, with the shared component's values as the
        /// defaults. Private because the named values above are the whole set:
        /// they are what keeps paint-building off the frame.
        private init(
            halo: Double = 0.30,
            outerRing: Double = 0.14,
            innerRing: Double = 0.42,
            coreGlow: Double = 0.50,
            coreGlowReach: Double = BreathGlyph.Proportion.coreGlow / BreathGlyph.Proportion.core
        ) {
            self.halo = Gradient(stops: [
                .init(color: Theme.Breath.inhale.opacity(halo), location: 0),
                .init(
                    color: Theme.Breath.inhale.opacity(0),
                    location: BreathGlyph.Proportion.haloFade
                ),
            ])
            self.outerRing = Theme.Breath.exhale.opacity(outerRing)
            self.innerRing = Theme.Breath.inhale.opacity(innerRing)
            core = CoreGlow(alpha: coreGlow, reach: coreGlowReach)
        }
    }

    /// One phase colour's paint for a core: the lit body, the flat fill it
    /// collapses to below the threshold, and the light it sheds past its own
    /// edge. Built only inside a `CoreGlow`, which every surface holds in a
    /// static — `body` runs at display refresh for the whole of a session,
    /// and building a gradient per frame was this drawing's whole cost.
    struct CorePaint: Sendable {
        /// The lit top of the core — vapour, not a token: the same value in
        /// both appearances, because the core is the phase colour everywhere
        /// and does not adapt.
        private static let vapour = Color(red: 0xEA / 255, green: 0xF7 / 255, blue: 0xFA / 255)

        let glow: Gradient
        let lit: Gradient
        let flat: Color

        init(phase: Color, alpha: Double, edge: Double) {
            glow = Gradient(stops: [
                .init(color: phase.opacity(alpha), location: edge),
                .init(color: phase.opacity(0), location: 1),
            ])
            lit = Gradient(stops: [
                .init(color: Self.vapour, location: 0),
                .init(color: phase, location: BreathGlyph.Proportion.coreDepth),
                .init(color: phase, location: 1),
            ])
            flat = phase
        }
    }

    /// A core's paint at one surface: how far its light reaches past its own
    /// edge, and the built paint for each phase colour it may wear. Hold one
    /// in a static — a gradient per frame is the cost this drawing's shared
    /// paints took out, and a tint mixed per frame would put it back.
    public struct CoreGlow: Sendable {
        /// No light at all, for a core under ``flatFillThreshold`` — it draws
        /// as a plain disc and sheds nothing, so a glow it carried would never
        /// be reached. Named rather than spelt as two zeroes at the call site,
        /// which reads as a choice about brightness instead of a consequence
        /// of the size.
        public static let flat = CoreGlow(alpha: 0, reach: 0)

        /// How wide a core and its light are together, as a multiple of the
        /// core's own diameter. The one place that rule is written: the
        /// gradient's edge stop, the field's frame and a surface sizing its
        /// drawing to a frame all read it rather than spelling it again.
        public let spread: Double
        let inhale: CorePaint
        let hold: CorePaint

        /// - Parameters:
        ///   - alpha: the glow's strength where the core's edge is.
        ///   - reach: how far past that edge it reaches, as a fraction of
        ///     the core's diameter.
        public init(alpha: Double, reach: Double) {
            // A ratio, not a size: one gradient serves every core.
            let spread = 1 + 2 * reach
            let edge = 1 / spread
            self.spread = spread
            inhale = CorePaint(phase: Theme.Breath.inhale, alpha: alpha, edge: edge)
            hold = CorePaint(phase: Theme.Breath.hold, alpha: alpha, edge: edge)
        }
    }

    /// The core alone at a diameter of the caller's choosing — the phone
    /// session's orb is this recipe at its own geometry rather than an
    /// instance of the glyph, over one built set of paints. Drawn at full
    /// inhale: the breath's scale and fade are the caller's to apply.
    public struct Core: View {
        let diameter: CGFloat
        let glow: CoreGlow
        let hold: Double

        /// - Parameters:
        ///   - diameter: the core at full inhale.
        ///   - glow: the light it sheds past that edge.
        ///   - hold: how much of the hold's colour it wears, 0...1. A number
        ///     off the phase clock, not a trigger — see `holdPresence`.
        public init(diameter: CGFloat, glow: CoreGlow, hold: Double) {
            self.diameter = diameter
            self.glow = glow
            self.hold = hold
        }

        /// Two cores dissolving, one paint over the other — a crossfade, not
        /// a mixed colour, because the paints are built and a gradient
        /// interpolated per frame is what this drawing may not do. The discs
        /// fade in over an opaque one so the ground never shows through the
        /// middle; the light either side fades out, or it would sum brighter.
        public var body: some View {
            ZStack {
                light(glow.inhale)
                    .opacity(1 - hold)
                light(glow.hold)
                    .opacity(hold)
                disc(glow.inhale)
                disc(glow.hold)
                    .opacity(hold)
            }
        }

        /// The light this phase colour sheds past the core's edge. Nothing
        /// below the flat-fill threshold, where the disc is the whole of what
        /// a core that size can carry.
        @ViewBuilder
        private func light(_ paint: CorePaint) -> some View {
            if diameter >= BreathGlyph.flatFillThreshold {
                let field = diameter * glow.spread

                Circle()
                    .fill(
                        RadialGradient(
                            gradient: paint.glow,
                            center: .center,
                            startRadius: 0,
                            endRadius: field / 2
                        )
                    )
                    .frame(width: field, height: field)
            }
        }

        /// The core itself: lit vapour falling to the phase colour, its
        /// gradient origin pulled above centre so the disc reads as a body
        /// catching light rather than a flat dot — keep the off-centre origin.
        /// Below the threshold it collapses to a flat fill.
        private func disc(_ paint: CorePaint) -> some View {
            Group {
                if diameter >= BreathGlyph.flatFillThreshold {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: paint.lit,
                                center: UnitPoint(x: 0.5, y: 0.32),
                                startRadius: 0,
                                endRadius: diameter / 2
                            )
                        )
                } else {
                    Circle()
                        .fill(paint.flat)
                }
            }
            .frame(width: diameter, height: diameter)
        }
    }

    /// How far each layer reaches, as a fraction of the frame.
    private enum Proportion {
        static let outerRing = 0.74
        static let innerRing = 0.50
        static let core = 0.293
        /// Where the halo's light has fully faded, as a fraction of its radius.
        static let haloFade = 0.66
        /// The core glow's reach past the core's edge — 60pt on the 300pt
        /// session frame.
        static let coreGlow = 0.2
        /// Where the core's gradient turns fully inhale-coloured.
        static let coreDepth = 0.75
    }

    /// Below this core diameter the gradient reads as noise, so the core
    /// becomes a flat fill and sheds no light. One surface is under the line
    /// on purpose: the compact Dynamic Island's 11-point core, which §3 asks
    /// for flat. The lock screen's 12.9-point glance clears it, which is what
    /// sizes that row's frame at 44.
    private static let flatFillThreshold: CGFloat = 12

    let side: CGFloat
    let pose: Pose
    let layers: Layers
    let strength: Strength

    /// - Parameters:
    ///   - side: the square frame this draws in; every layer is a ratio of it.
    ///   - pose: the breath at this instant.
    ///   - layers: which layers this surface affords.
    ///   - strength: how loudly it paints them.
    public init(
        side: CGFloat,
        pose: Pose,
        layers: Layers,
        strength: Strength = .standard
    ) {
        self.side = side
        self.pose = pose
        self.layers = layers
        self.strength = strength
    }

    public var body: some View {
        ZStack {
            if layers.contains(.halo) {
                halo
            }
            if layers.contains(.outerRing) {
                ring(Proportion.outerRing, stroke: strength.outerRing)
            }
            if layers.contains(.innerRing) {
                ring(Proportion.innerRing, stroke: strength.innerRing)
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
                    gradient: strength.halo,
                    center: .center,
                    startRadius: 0,
                    endRadius: side / 2
                )
            )
            .scaleEffect(pose.coreScale)
            .opacity(pose.coreOpacity)
    }

    /// One passive ring, breathing with the pair's shared scale.
    private func ring(_ proportion: Double, stroke: Color) -> some View {
        Circle()
            .stroke(stroke, lineWidth: 1)
            .frame(width: side * proportion, height: side * proportion)
            .scaleEffect(pose.ringScale)
    }

    /// The core at this frame's size, breathing, and wearing the hold's
    /// colour as far as the hold has arrived.
    private var core: some View {
        let diameter = side * Proportion.core

        return Core(diameter: diameter, glow: strength.core, hold: pose.holdPresence)
            .scaleEffect(pose.coreScale)
            // The flat fill keeps full opacity: at that size the breath's fade
            // reads as an empty region rather than empty lungs, so the scale
            // alone carries the travel.
            .opacity(diameter >= Self.flatFillThreshold ? pose.coreOpacity : 1)
    }
}
