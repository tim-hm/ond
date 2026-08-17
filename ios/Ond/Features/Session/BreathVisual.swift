import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The thing you watch while you breathe.
///
/// One value, two renderings, and only ever one on screen. The glyph is the
/// guide: the shared five-layer breathing shape, posed by the session's own
/// clock, with the hold ring marking the stillness. The ring fills its arc
/// over the phase instead, which is what Reduce Motion draws whatever the
/// setting says, since a body that scales for ten minutes is exactly the
/// motion that setting exists to suppress.
///
/// The whole-session progress ring this used to wear is gone with the refresh
/// — the header's remaining time carries that number now, and the glyph's
/// rings belong to the breath alone.
struct BreathVisual: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    /// The whole plan, not just the beat: the glyph's hold ring crossfades
    /// across phase boundaries, which only the timeline can see.
    let timeline: SessionTimeline
    let accent: Color
    /// Which drawing the moment asked for. Passed rather than read off `beat`,
    /// which carries one: this draws before the first beat exists, and a guide
    /// that changed shape a frame in would announce itself.
    let register: CopyRegister

    /// How much room the drawing takes at the default text size.
    static let extent: CGFloat = 300

    /// How far a soft-bodied guide's gradient reaches: the padded radius the
    /// drawing actually occupies.
    ///
    /// The subtraction is not decorative — the playful drawing pads its guide
    /// by `Theme.Spacing.close`, and a gradient that stopped at the unpadded
    /// radius would be clipped, printing the very edge line a soft body exists
    /// to avoid. Shared with `PlayfulBreathVisual`'s flower so retuning the
    /// padding cannot leave one of the two drawings on the old geometry.
    ///
    /// - Parameter side: the room this drawing is taking, which is `fitted`
    ///   rather than the static above once Dynamic Type has had its say.
    static func bodyReach(within side: CGFloat) -> CGFloat {
        side / 2 - Theme.Spacing.close
    }

    /// Whether the filling arc is the guide on screen rather than the glyph.
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
    /// The player is a plain `VStack` with no scroll view — a guide holding its
    /// full extent while the instruction, the passage hint and the countdown
    /// all roughly doubled collapsed both `Spacer`s and then pushed the
    /// transport controls off the bottom of the screen, and those controls are
    /// the only way to stop a session. The room the words take has to come
    /// from the one element on the screen that can give it up and still be
    /// followed.
    ///
    /// A proportion rather than a measurement, which is the honest limitation:
    /// it answers to the text size and not to the screen's height, so it is a
    /// bound on the overflow rather than a proof against it.
    ///
    /// One-sided. Below the default text size the words take *less* room, and
    /// the same ratio would have spent it on a guide larger than the one this
    /// screen was drawn around — growth is what `extent` already is.
    private var fitted: CGFloat {
        Self.extent * min(max(1 / typeGrowth, Self.mostShrink), 1)
    }

    var body: some View {
        // Read once. This body runs at display refresh, and `fitted` goes
        // through a `ScaledMetric` the frame and both drawings would otherwise
        // each ask separately.
        let fitted = fitted

        return Group {
            // The ring wins over the register, both ways round. Reduce
            // Motion is not a preference the route may talk past, and
            // somebody who chose Ring chose how they read a breath — a
            // playful session is still their session, and the words and the
            // colour are already saying whose it is.
            if Self.drawsArc(reduceMotion: reduceMotion, settings) {
                ring
                    .accessibilityIdentifier("breath-guide-ring")
                    .padding(Theme.Spacing.close)
                    .animation(.easeInOut(duration: 0.4), value: isStill)
            } else if register == .playful {
                PlayfulBreathVisual(
                    kind: beat?.kind,
                    level: SessionTimeline.Beat.level(ofFullness: fullness),
                    tint: tint,
                    extent: fitted
                )
                .accessibilityIdentifier("breath-guide-playful")
                .padding(Theme.Spacing.close)
                .animation(.easeInOut(duration: 0.4), value: isStill)
            } else {
                BreathGlyph(
                    side: fitted,
                    pose: BreathGlyph.Pose(timeline: timeline, elapsed: elapsed)
                )
                .accessibilityIdentifier("breath-guide-sphere")
            }
        }
        .frame(width: fitted, height: fitted)
    }

    /// The hold's indigo while the breath is held, the goal's accent while it
    /// moves — for the two drawings that mark a hold with colour alone. The
    /// glyph does not read this: its hold ring is the phase colour on every
    /// session, and the goal stays on the surround.
    private var tint: Color {
        isStill ? Theme.Breath.hold : accent
    }

    /// Whether the breath is being held — the one phase where nothing scales.
    private var isStill: Bool {
        beat?.kind.isHold ?? false
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
        .padding(Theme.Spacing.loose)
    }

    /// How full the lungs are: `emptyLungs` at rest through to 1 at the top.
    /// Empty before the first beat, which is where a breath starts from.
    private var fullness: Double {
        beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
    }
}
