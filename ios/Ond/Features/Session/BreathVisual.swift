import OndKit
import OndUI
import SwiftUI

/// The thing you watch while you breathe.
///
/// One value, two renderings, and only ever one on screen. The sphere is the
/// guide: a soft-edged body swelling on the inhale and contracting on the
/// exhale, with no stroke anywhere on it — the size is the instruction and the
/// colour marks the holds. The ring fills its arc over the phase instead, which
/// is what Reduce Motion draws whatever the setting says, since a body that
/// scales for ten minutes is exactly the motion that setting exists to
/// suppress.
struct BreathVisual: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// How far through the whole session, 0...1 — the outer ring's fill.
    let progress: Double
    let accent: Color
    /// Which drawing the moment asked for. Passed rather than read off `beat`,
    /// which carries one: this draws before the first beat exists, and a guide
    /// that changed shape a frame in would announce itself.
    let register: CopyRegister

    /// How much room the drawing takes at the default text size, which is also
    /// how much ground has to be restored under it — one number, so the patch
    /// cannot be sized against a figure that has since grown.
    static let extent: CGFloat = 260

    /// How far a soft-bodied guide's gradient reaches: the padded radius the
    /// drawing actually occupies.
    ///
    /// The subtraction is not decorative — `body` pads the guide by
    /// `Theme.Spacing.close`, and a gradient that stopped at the unpadded radius
    /// would be clipped, printing the very edge line a soft body exists to
    /// avoid. Shared with `PlayfulBreathVisual`'s flower so retuning the padding
    /// cannot leave one of the two drawings on the old geometry.
    ///
    /// - Parameter side: the room this drawing is taking, which is `fitted`
    ///   rather than the static above once Dynamic Type has had its say.
    static func bodyReach(within side: CGFloat) -> CGFloat {
        side / 2 - Theme.Spacing.close
    }

    /// Whether the filling arc is the guide on screen rather than the scaling
    /// body.
    ///
    /// Static, and asked by `SessionPlayerView` as well as by `body` below: the
    /// player caps its frame timeline for exactly the case this answers, and a
    /// player testing only `reduceMotion` left somebody who chose Ring in
    /// Settings sweeping an arc at the display's own rate for ten minutes — the
    /// battery cost the cap exists to avoid, on the one route that asked for the
    /// arc deliberately.
    static func drawsArc(reduceMotion: Bool, _ settings: SessionSettings) -> Bool {
        reduceMotion || settings.breathVisual == .ring
    }

    @Environment(SessionSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The session ring's stroke. Thin on purpose: it is reference, not
    /// instruction, and the guide inside it is the thing being followed.
    private static let sessionLineWidth: CGFloat = 3

    /// The breath ring's stroke. Heavy, because at this size it is the whole
    /// drawing rather than a mark at its edge.
    private static let breathLineWidth: CGFloat = 12

    /// How far the guide may ever shrink, as a fraction of `extent`.
    ///
    /// The bound `displayNumeral(size:)` puts on growth, turned around: a guide
    /// already gives up its share of the screen at the default size, and one
    /// taken below this is a figure being watched rather than followed. At the
    /// largest accessibility setting the words grow by about 1.76, so this is
    /// very nearly what the ratio asks for anyway — it is here to stop the next
    /// text step, whatever it is, from shrinking the guide without limit.
    private static let mostShrink: CGFloat = 0.6

    /// `extent` as Dynamic Type would have grown it — read to derive the growth,
    /// never drawn at.
    ///
    /// Measured against `.largeTitle` for `displayNumeral(size:)`'s reason: the
    /// countdown under this guide grows on that curve, so the guide gives back
    /// the ratio the numeral takes rather than one tuned separately.
    @ScaledMetric(relativeTo: .largeTitle) private var grown: CGFloat = BreathVisual.extent

    /// How much larger Dynamic Type has made the words around the guide — 1 at
    /// the default setting, about 1.76 at the largest.
    private var typeGrowth: CGFloat {
        grown / Self.extent
    }

    /// The room the drawing actually takes: the design extent given back in the
    /// proportion the words around it grew by, floored at `mostShrink`.
    ///
    /// The player is a plain `VStack` with no scroll view — a guide holding 260
    /// points while the instruction, the passage hint and the countdown all
    /// roughly doubled collapsed both `Spacer`s and then pushed the transport
    /// controls off the bottom of the screen, and those controls are the only way
    /// to stop a session. The room the words take has to come from the one
    /// element on the screen that can give it up and still be followed.
    ///
    /// A proportion rather than a measurement, which is the honest limitation:
    /// it answers to the text size and not to the screen's height, so it is a
    /// bound on the overflow rather than a proof against it.
    private var fitted: CGFloat {
        Self.extent * max(1 / typeGrowth, Self.mostShrink)
    }

    var body: some View {
        // Read once. This body runs at display refresh, and `fitted` goes
        // through a `ScaledMetric` the frame, the sphere's gradient and the
        // playful drawing would otherwise each ask separately.
        let fitted = fitted

        return ZStack {
            sessionRing

            Group {
                // The ring wins over the register, both ways round. Reduce
                // Motion is not a preference the route may talk past, and
                // somebody who chose Ring chose how they read a breath — a
                // playful session is still their session, and the words and the
                // colour are already saying whose it is.
                if Self.drawsArc(reduceMotion: reduceMotion, settings) {
                    ring
                } else if register == .playful {
                    PlayfulBreathVisual(
                        kind: beat?.kind,
                        level: SessionTimeline.Beat.level(ofFullness: fullness),
                        tint: tint,
                        extent: fitted
                    )
                } else {
                    sphere(within: fitted)
                }
            }
            // Clear of the ring, so a full inhale tops out just inside it
            // rather than swallowing it.
            .padding(Theme.Spacing.close)
        }
        .frame(width: fitted, height: fitted)
        .animation(.easeInOut(duration: 0.4), value: isStill)
        // The session ring is the accent at full strength, which measures
        // 2.45:1 against the top of the wash it was sitting on — under the 3:1
        // WCAG 1.4.11 asks of a mark that carries meaning. Restoring the ground
        // is what fixes that, and it is also what would let a stroked breath
        // figure take this slot, since the wash carries two legible marks where
        // a figure needs four. The sphere itself was never in danger, being a
        // fill rather than a stroke.
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

    /// Whether the breath is being held — the one phase where nothing scales,
    /// which is why it gets the colour.
    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }

    /// The guide: solid at heart, falling to nothing by the rim, scaled by the
    /// breath.
    ///
    /// No stroke on it at all. An edge drawn as a line reads as a boundary to
    /// hit, and a breath does not have one — the soft border is the drawing
    /// saying that the lungs are somewhere around here rather than exactly
    /// there. The gradient's reach subtracts the padding so it hits clear at the
    /// body's actual rim; cut short, the clipped edge prints as the very line
    /// this shape exists to avoid.
    ///
    /// - Parameter side: the room the drawing has, so the gradient's reach is
    ///   the one `body` sized the frame with.
    private func sphere(within side: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: tint.opacity(0.9), location: 0),
                        .init(color: tint.opacity(0.65), location: 0.7),
                        .init(color: tint.opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.bodyReach(within: side)
                )
            )
            .scaleEffect(fullness)
    }

    /// The other guide: the phase's own progress as a filling arc, for anybody
    /// who reads a gauge faster than a body — and for Reduce Motion, where it is
    /// the only one drawn.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: Self.breathLineWidth)
            Circle()
                .trim(from: 0, to: beat?.fraction(at: elapsed) ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: Self.breathLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(24)
    }

    /// How full the lungs are: `emptyLungs` at rest through to 1 at the top.
    /// Empty before the first beat, which is where a breath starts from.
    private var fullness: Double {
        beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
    }
}
