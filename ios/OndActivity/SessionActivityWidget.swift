import ActivityKit
import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// önd's one Live Activity, in all four of the presentations the system asks
/// for: the lock screen, and the Dynamic Island expanded, compact and minimal.
///
/// Every Island region draws the breath as `BreathCue`'s sweeping ring, because
/// a widget cannot animate: anything posed from the payload alone shows the
/// phase's two end points and nothing between them, while a timer ring is
/// handed to the system as the phase's window and swept locally at full
/// fidelity. The compact pair is about a word wide each, so the ring takes the
/// leading region and the phase's own word — "In", "Hold", "Out" — takes the
/// trailing one. Between them a glance answers "which phase am I in, and how
/// far through" without reading a sentence. The expanded presentation keeps the
/// shared glyph and rings it, so its orb and the compact cue say the same thing
/// at two sizes.
struct SessionActivityWidget: Widget {
    /// The expanded leading region's footprint, unchanged by the ring: the ring
    /// takes the old glyph's 56 points and the glyph draws inside it, so the
    /// cue sentence and the remaining time beside it do not move.
    private static let expandedCue: CGFloat = 56
    /// The glyph inside that ring. Its halo has faded out well before its own
    /// edge — `BreathGlyph.Proportion.haloFade` — so the gap this leaves is
    /// clear of the orb's light rather than clipping it, and 48 keeps the core
    /// above the 12-point flat-fill threshold that would cost it the lit
    /// treatment.
    private static let expandedGlyph: CGFloat = 48
    /// The compact and minimal ring. Both regions are the same small square.
    private static let compactCue: CGFloat = 20

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreenView(attributes: context.attributes, presence: context.state)
        } dynamicIsland: { context in
            // The session's colour, not the goal's: a playful route is rose in
            // the app, and an Island still drawing the goal's blue would put two
            // colours on one breath.
            let accent = context.state.register.accent(over: context.attributes.goal)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        BreathCue(
                            presence: context.state,
                            accent: accent,
                            diameter: Self.expandedCue
                        )
                        BreathGlyph(
                            side: Self.expandedGlyph,
                            pose: .pushed(for: context.state),
                            layers: .card
                        )
                    }
                    .padding(.leading, Theme.Spacing.close)
                }
                DynamicIslandExpandedRegion(.center) {
                    SessionCueLabel(attributes: context.attributes, presence: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionRemainingTime(presence: context.state, showsSuffix: true)
                        .font(.title3)
                        .padding(.trailing, Theme.Spacing.close)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionControls(
                        attributes: context.attributes,
                        presence: context.state
                    )
                    .padding(.top, Theme.Spacing.close)
                }
            } compactLeading: {
                BreathCue(
                    presence: context.state,
                    accent: accent,
                    diameter: Self.compactCue
                )
            } compactTrailing: {
                phaseWord(context.state)
                    .font(.caption.weight(.medium))
                    // The hold shift the ring beside it already makes, so the
                    // pair moves as one rather than the word staying accent-
                    // coloured through a hold the ring has gone indigo for.
                    .foregroundStyle(context.state.cueTint(over: .primary))
                    // On the element rather than inside `phaseWord`'s branches:
                    // "In" is not the sentence VoiceOver should read, and
                    // unlabelled the pause branch falls back to the SF Symbol's
                    // own description. One label covers both, and it is the
                    // sentence with the nostril in it.
                    .accessibilityLabel(context.state.spokenInstruction)
            } minimal: {
                BreathCue(
                    presence: context.state,
                    accent: accent,
                    diameter: Self.compactCue
                )
                // The one presentation with no words beside the cue, so the
                // cue answers for itself.
                .accessibilityElement()
                .accessibilityLabel(context.state.spokenInstruction)
            }
            .keylineTint(accent)
        }
    }

    /// The phase in a word, or the pause glyph where there is none — a nil
    /// `cueWord` is a paused session, which is not an in, an out or a hold, and
    /// which "Paused" is too long a word to say here.
    @ViewBuilder
    private func phaseWord(_ presence: SessionPresence) -> some View {
        if let word = presence.cueWord {
            Text(word).lineLimit(1)
        } else {
            Image(systemName: "pause.fill")
        }
    }
}
