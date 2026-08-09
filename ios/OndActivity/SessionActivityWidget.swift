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
/// surface. Its two regions are about a word wide each, so the dot takes the
/// leading one — its size *is* the phase — and the trailing one takes the phase
/// in one word. Between them a glance answers "which phase am I in" without
/// reading a sentence, which is the bar the ticket sets and the reason a
/// progress bar would not have met it.
struct SessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreenView(attributes: context.attributes, presence: context.state)
        } dynamicIsland: { context in
            let accent = context.attributes.goal.accent

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BreathCue(presence: context.state, accent: accent, diameter: 40)
                        .padding(.leading, Theme.Spacing.close)
                }
                DynamicIslandExpandedRegion(.center) {
                    SessionCueLabel(attributes: context.attributes, presence: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionControls(presence: context.state, accent: accent)
                        .padding(.top, Theme.Spacing.close)
                }
            } compactLeading: {
                BreathCue(presence: context.state, accent: accent, diameter: 20)
            } compactTrailing: {
                phaseWord(context.state)
                    .font(.caption.weight(.medium))
            } minimal: {
                BreathCue(presence: context.state, accent: accent, diameter: 20)
                    // The one presentation with no words beside the cue, so the
                    // cue answers for itself.
                    .accessibilityElement()
                    .accessibilityLabel(context.state.spokenInstruction)
            }
            .keylineTint(accent)
        }
    }

    /// The phase in one word, or the pause glyph — a paused session must not go
    /// on naming a breath nobody is taking.
    @ViewBuilder
    private func phaseWord(_ presence: SessionPresence) -> some View {
        if case .paused = presence.stance {
            Image(systemName: "pause.fill")
        } else {
            Text(presence.breath.kind.shortInstruction)
        }
    }
}
