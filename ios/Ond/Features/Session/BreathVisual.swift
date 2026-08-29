import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The thing you watch while you breathe: one value, two renderings, only one
/// on screen. The glyph is the guide, posed by the session's clock. The ring
/// fills its arc over the phase and is what Reduce Motion draws whatever the
/// setting says — a body scaling for ten minutes is the motion that setting
/// suppresses. The whole-session number stays in the header, never here.
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

    /// Whether the filling arc is the guide on screen rather than the glyph.
    /// Static because `SessionPlayerView` asks it too, to cap its frame
    /// timeline: a player testing only `reduceMotion` left somebody who chose
    /// Ring in Settings sweeping an arc at the display's own rate for ten
    /// minutes — the battery cost the cap exists to avoid.
    static func drawsArc(reduceMotion: Bool, _ settings: SessionSettings) -> Bool {
        reduceMotion || settings.breathVisual == .ring
    }

    @Environment(SessionSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The breath ring's stroke. Heavy, because at this size it is the whole
    /// drawing rather than a mark at its edge.
    private static let breathLineWidth: CGFloat = 12

    /// How far the guide may ever shrink, as a fraction of `extent`. The
    /// fraction holds the absolute floor at 156 points, where it sat before
    /// the extent grew: the refresh made the guide larger at the default
    /// size, not to take more of an accessibility screen whose transport
    /// controls already fight for the bottom edge.
    private static let mostShrink: CGFloat = 0.52

    /// `extent` as Dynamic Type would have grown it — read to derive the
    /// growth, never drawn at. Measured against `.largeTitle` because the
    /// countdown under this guide grows on that curve, so the guide gives
    /// back the ratio the numeral takes rather than one tuned separately.
    @ScaledMetric(relativeTo: .largeTitle) private var grown: CGFloat = BreathVisual.extent

    /// How much larger Dynamic Type has made the words around the guide — 1 at
    /// the default setting, about 1.76 at the largest.
    private var typeGrowth: CGFloat {
        grown / Self.extent
    }

    /// The design extent given back in the proportion the words grew by,
    /// floored at `mostShrink`. Large type once pushed the transport controls
    /// — the only way to stop a session — off screen; only the guide can give
    /// up room. A proportion answers to text size, not screen height: a bound
    /// on overflow, not a proof. One-sided — below the default size it never grows.
    private var fitted: CGFloat {
        Self.extent * min(max(1 / typeGrowth, Self.mostShrink), 1)
    }

    var body: some View {
        // Read once each. This body runs at display refresh: `fitted` goes
        // through a `ScaledMetric` the frame and both drawings would otherwise
        // each ask separately, and the arc question decides two branches.
        let fitted = fitted
        let drawsArc = Self.drawsArc(reduceMotion: reduceMotion, settings)

        return Group {
            // The ring wins over the register, both ways round. Reduce
            // Motion is not a preference the route may talk past, and
            // somebody who chose Ring chose how they read a breath — a
            // playful session is still their session, and the words and the
            // colour are already saying whose it is.
            if drawsArc || register == .playful {
                Group {
                    if drawsArc {
                        ring
                            .accessibilityIdentifier("breath-guide-ring")
                    } else {
                        PlayfulBreathVisual(
                            kind: beat?.kind,
                            level: SessionTimeline.Beat.level(ofFullness: fullness),
                            tint: tint,
                            extent: fitted
                        )
                        .accessibilityIdentifier("breath-guide-playful")
                    }
                }
                .padding(Theme.Spacing.close)
                .animation(.easeInOut(duration: 0.4), value: isStill)
            } else {
                BreathGlyph(
                    side: fitted,
                    pose: BreathGlyph.Pose(timeline: timeline, elapsed: elapsed)
                )
                .accessibilityIdentifier("breath-guide-glyph")
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
        PhaseArc(
            fraction: beat?.fraction(at: elapsed) ?? 0,
            tint: tint,
            lineWidth: Self.breathLineWidth
        )
        .padding(Theme.Spacing.loose)
    }

    /// How full the lungs are: `emptyLungs` at rest through to 1 at the top.
    /// Empty before the first beat, which is where a breath starts from.
    private var fullness: Double {
        beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
    }
}
