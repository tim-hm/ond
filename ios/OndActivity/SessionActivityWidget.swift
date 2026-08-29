import ActivityKit
import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// önd's one Live Activity, in all four presentations: the lock screen, and
/// the Dynamic Island expanded, compact and minimal. The Island inverts the
/// breath: `BreathCue`'s ring sweeps the phase and every core under it holds
/// still. The compact pair puts the ring leading and the phase word trailing,
/// and the expanded region says the same thing larger.
struct SessionActivityWidget: Widget {
    /// The ring the compact and minimal regions share, which must stay one
    /// number across the two.
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
                    // The ring owns the region's 56 points and the glyph
                    // draws at 48 inside it. The gap clears the orb's light
                    // rather than clipping it, because the halo has faded out
                    // well before its own edge; and 48 holds the core above the
                    // flat-fill threshold that would cost it the lit treatment.
                    ZStack {
                        BreathCue(presence: context.state, accent: accent, diameter: 56)
                        BreathGlyph(
                            side: 48,
                            pose: .sweeping(for: context.state),
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
                compactCue(context.state, accent: accent)
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
                compactCue(context.state, accent: accent)
                    // The one presentation with no words beside the cue, so the
                    // cue answers for itself.
                    .accessibilityElement()
                    .accessibilityLabel(context.state.spokenInstruction)
            }
            .keylineTint(accent)
        }
    }

    /// The ring the compact and minimal regions both draw, at the one size they
    /// share.
    private func compactCue(_ presence: SessionPresence, accent: Color) -> some View {
        BreathCue(presence: presence, accent: accent, diameter: Self.compactCue)
    }

    /// The phase in a word, or the pause glyph where there is none — a nil
    /// `cueWord` is a paused session, which is not an in, an out or a hold, and
    /// which "Paused" is too long a word to say here.
    @ViewBuilder
    private func phaseWord(_ presence: SessionPresence) -> some View {
        if let word = presence.cueWord {
            Text(word)
        } else {
            Image(systemName: "pause.fill")
        }
    }
}
