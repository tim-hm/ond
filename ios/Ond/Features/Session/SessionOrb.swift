import OndKit
import OndUI
import SwiftUI

/// The live session's orb — the shared geometry's derivative rather than an
/// instance of it. The core is the breath, the arc is the session, and the
/// extent ring says how much further; an exercise may add a tail on the side
/// it breathes through, or the mark a stacked inhale overshoots. The drifting
/// light behind all of it is the screen's, and never follows the phase.
struct SessionOrb: View {
    /// The beat on screen, for the two marks an exercise may add to the orb.
    let beat: SessionTimeline.Beat?
    /// How full the lungs are: 0 at the bottom of a breath, 1 at the top.
    let level: Double
    /// Whether `level` is the breath moving, or a parked value a sweeping ring
    /// draws the phase beside. The marks that measure against a growing core
    /// have nothing to measure once it stops.
    let coreTravels: Bool
    /// How present the hold is, 0...1 — the core wears the hold's colour by
    /// it. Nothing else on this screen carries the hold's own indigo.
    let hold: Double
    /// How far through the whole session, 0...1 — the arc's sweep.
    let progress: Double
    /// The square this draws in, the core's light included.
    let extent: CGFloat

    /// How much of the orb's own circle the core fills, at the bottom of a
    /// breath and at the top of one.
    private static let restExtent = 0.40
    private static let fullExtent = 0.92

    /// The shared core's own light. §3's reach, kept as the ratio it was drawn
    /// at — 60 points on that drawing's 276-point core — so the light scales
    /// with the core rather than swamping a smaller one.
    private static let coreGlow = BreathGlyph.CoreGlow(alpha: 0.5, reach: 60.0 / 276)

    /// The circle the core and its light are drawn on, as a fraction of the
    /// frame. Read off the glow's own spread, so a breath at its fullest sheds
    /// its last light exactly on the extent ring however the two are retuned.
    /// The spec's §6 draws the core on the whole frame, which throws that
    /// light 48 points past the ring and over the words.
    private static let figureExtent = 1 / (fullExtent * coreGlow.spread)

    /// `extent`'s figure, for the sweeping arc, which is wound outside this
    /// view and has the same core to clear.
    static func figure(in extent: CGFloat) -> CGFloat {
        extent * figureExtent
    }

    /// The hairline the arc rides, and the mark a stacked inhale leaves
    /// behind. Held rather than mixed in `body`, which runs at display refresh.
    private static let extentStroke = Theme.Breath.exhale.opacity(0.2)
    private static let overshootStroke = Theme.Breath.exhale.opacity(0.35)
    private static let overshootDash = StrokeStyle(lineWidth: 1, dash: [4, 6])

    /// A sided breath's tail: how far it reaches out of the centre, as a
    /// fraction of the orb's circle, so it gives room back with the orb when
    /// large type shrinks it. Its fall away from the centre is built once, for
    /// the same reason the strokes are.
    private static let tailReach = 74.0 / 300
    private static let tailWidth: CGFloat = 2
    private static let tailFill = LinearGradient(
        colors: [Theme.Breath.inhale.opacity(0.55), Theme.Breath.inhale.opacity(0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var figure: CGFloat {
        Self.figure(in: extent)
    }

    var body: some View {
        ZStack {
            core
            extentRing
            SessionArc(fraction: progress)
            if let side = beat?.passage?.side {
                tail(towards: side)
            }
            // Over the core rather than under it: the mark's whole job is to
            // stay visible while the sip grows past it.
            if let overshootDiameter {
                Circle()
                    .stroke(Self.overshootStroke, style: Self.overshootDash)
                    .frame(width: overshootDiameter, height: overshootDiameter)
            }
        }
        .frame(width: extent, height: extent)
        .accessibilityHidden(true)
    }

    /// The breath: the shared core recipe at this surface's own geometry,
    /// drawn at the top of the breath and scaled back to where the lungs are.
    private var core: some View {
        BreathGlyph.Core(diameter: figure * Self.fullExtent, glow: Self.coreGlow, hold: hold)
            .scaleEffect(coreScale)
    }

    /// The core's travel as a fraction of its full-inhale size — the frame
    /// cancels out of the ratio, so this is a scale and not a second diameter.
    private var coreScale: Double {
        let rest = Self.restExtent / Self.fullExtent

        return rest + (1 - rest) * level
    }

    /// The travel's outer edge, held still while the core grows toward it, so
    /// how much further there is to go is read rather than guessed. On the
    /// frame's own edge, where the core's light reaches it at the top of a
    /// breath: the disc stops short of that, and the air between the two is
    /// what §6 draws the pair with.
    private var extentRing: some View {
        Circle()
            .stroke(Self.extentStroke, lineWidth: 0.5)
    }

    /// The one mark sided breathing adds: a tail out of the orb's centre on
    /// the side being breathed through, brightest where it leaves the centre.
    /// Left is the practitioner's own left, which is the side of the screen
    /// they see it on — not the sign `Passage.Side` carries for a figure.
    private func tail(towards side: Passage.Side) -> some View {
        let length = figure * Self.tailReach
        let outward: CGFloat = side == .left ? -1 : 1

        return Capsule()
            .fill(Self.tailFill)
            .frame(width: length, height: Self.tailWidth)
            .rotationEffect(.degrees(side == .left ? 180 : 0))
            .offset(x: outward * length / 2)
    }

    /// Where the first inhale ended, while a second one is stacked on top of
    /// it — the physiological sigh's top-up, and nothing else in the
    /// catalogue. Only where the core travels: the mark is read as the core
    /// growing past it, and a parked core never does.
    private var overshootDiameter: CGFloat? {
        guard coreTravels, let beat, beat.stacksOnPrevious else { return nil }

        let level = SessionTimeline.Beat.level(ofFullness: beat.startFullness)

        return figure * (Self.restExtent + (Self.fullExtent - Self.restExtent) * level)
    }
}
