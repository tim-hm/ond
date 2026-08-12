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
/// surface. Its two regions are about a word wide each, so the ring takes the
/// leading one — its sweep is the phase running out — and the trailing one
/// takes the phase in one word. Between them a glance answers "which phase am
/// I in" without reading a sentence — the bar the ticket sets, and the reason
/// the sweep never stands alone where there is room for a word beside it.
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
                    BreathCue(presence: context.state, accent: accent, diameter: 40)
                        .padding(.leading, Theme.Spacing.close)
                }
                DynamicIslandExpandedRegion(.center) {
                    SessionCueLabel(attributes: context.attributes, presence: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionControls(
                        attributes: context.attributes,
                        presence: context.state,
                        accent: accent
                    )
                    .padding(.top, Theme.Spacing.close)
                }
            } compactLeading: {
                BreathCue(presence: context.state, accent: accent, diameter: 20)
            } compactTrailing: {
                phaseWord(context.state)
                    .font(.caption.weight(.medium))
                    // On the element rather than inside `phaseWord`'s paused
                    // branch: the running branch abbreviates to fit the region,
                    // and unlabelled the pause branch falls back to the SF
                    // Symbol's own description. One label covers both, and it is
                    // the sentence `minimal` beside it already speaks.
                    .accessibilityLabel(context.state.spokenInstruction)
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
        if presence.isPaused {
            Image(systemName: "pause.fill")
        } else {
            Text(presence.breath.kind.shortInstruction)
        }
    }
}
