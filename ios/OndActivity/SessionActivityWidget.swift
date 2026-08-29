import ActivityKit
import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// önd's one Live Activity, in all four presentations: the lock screen, and
/// the Dynamic Island expanded, compact and minimal. The Island inverts the
/// breath: `BreathCue`'s ring sweeps the phase and every core under it holds
/// still. The compact pair puts the geometry leading and the phase count
/// trailing, and the expanded region says the same thing larger.
struct SessionActivityWidget: Widget {
    /// The geometry the compact and minimal regions share, which must stay one
    /// number across the two, and the core inside it. §3 sizes that core at 11
    /// points rather than the shared 0.293 of the frame, which puts it under
    /// `BreathGlyph`'s flat-fill threshold — where §3 wants it.
    private static let compactCue: CGFloat = 26
    private static let compactCore: CGFloat = 11

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
                        .font(.title2)
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
                phaseCount(context.state)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Breath.exhale)
                    // On the element rather than inside `phaseCount`'s
                    // branches: a bare number is not what VoiceOver should
                    // read, and unlabelled the pause branch falls back to the
                    // SF Symbol's own description. One label covers every
                    // branch, and it is the sentence with the nostril in it.
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

    /// The geometry the compact and minimal regions both draw, at the one size
    /// they share: the sweeping ring, and the parked core §3 never drops.
    private func compactCue(_ presence: SessionPresence, accent: Color) -> some View {
        ZStack {
            BreathCue(presence: presence, accent: accent, diameter: Self.compactCue)
            BreathGlyph.Core(
                diameter: Self.compactCore,
                glow: .flat,
                hold: BreathGlyph.Pose.sweeping(for: presence).holdPresence
            )
        }
    }

    /// How long is left in this phase, or the pause glyph where nothing is
    /// running. The Island shows this on every phase rather than only during
    /// holds: with no word beside it the number is not a third line competing,
    /// it is the only thing there. Counted by the system off the phase's own
    /// window, which is the only live number an extension can draw.
    @ViewBuilder
    private func phaseCount(_ presence: SessionPresence) -> some View {
        if let window = presence.window {
            Text(timerInterval: window, pauseTime: nil, countsDown: true, showsHours: false)
        } else if let since = presence.heldSince {
            Text(since, style: .timer)
        } else {
            Image(systemName: "pause.fill")
        }
    }
}
