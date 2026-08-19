import ActivityKit
import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// önd's one Live Activity, in all four of the presentations the system asks
/// for: the lock screen, and the Dynamic Island expanded, compact and minimal.
///
/// The compact pair is the one that has to carry the whole point of this
/// surface. Its two regions are about a word wide each, so the breath takes
/// the leading one — the shared glyph's dot, pushed to the phase's target
/// state — and the trailing one takes the phase's own count, which the system
/// runs locally between pushes. Between them a glance answers "which phase am
/// I in, and for how much longer" without reading a sentence. The minimal
/// presentation keeps `BreathCue`'s sweeping ring instead of the dot — its
/// doc says why.
struct SessionActivityWidget: Widget {
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
                    BreathGlyph(
                        side: 56,
                        pose: .pushed(for: context.state),
                        layers: .card
                    )
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
                BreathGlyph(
                    side: 26,
                    pose: .pushed(for: context.state),
                    layers: .dot,
                    coreDiameterOverride: 11
                )
            } compactTrailing: {
                phaseCount(context.state)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    // The hold shift the dot beside it cannot carry — `.dot`
                    // draws the core alone — so the count's ink is what marks
                    // a timed hold apart from the inhale it would otherwise
                    // mirror.
                    .foregroundStyle(context.state.cueTint(over: .primary))
                    // On the element rather than inside `phaseCount`'s
                    // branches: a bare number labels nothing, and unlabelled
                    // the pause branch falls back to the SF Symbol's own
                    // description. One label covers all three, and it is the
                    // sentence `minimal` beside it already speaks.
                    .accessibilityLabel(context.state.spokenInstruction)
            } minimal: {
                BreathCue(presence: context.state, accent: accent)
                    // The one presentation with no words beside the cue, so the
                    // cue answers for itself.
                    .accessibilityElement()
                    .accessibilityLabel(context.state.spokenInstruction)
            }
            .keylineTint(accent)
        }
    }

    /// The shared count, or the pause glyph where there is none — a nil
    /// `cueCount` is a paused session, the one state with nothing to count.
    @ViewBuilder
    private func phaseCount(_ presence: SessionPresence) -> some View {
        if let count = presence.cueCount {
            // The timer text reserves width for the longest string it might
            // ever draw, which stretches a compact region; a breath's window
            // is seconds, so cap it at four digits' worth and pin the digits
            // to the island's trailing edge. The cap stays off the pause
            // glyph below, which must not take a flexible frame.
            count
                .lineLimit(1)
                .frame(maxWidth: 44, alignment: .trailing)
        } else {
            Image(systemName: "pause.fill")
        }
    }
}
