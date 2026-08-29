import OndKit
import OndStyle
import SwiftUI

/// The Island's breath cue: a timer ring that sweeps the current phase.
/// A widget steps between snapshots, so the system-interpolated ring is the
/// only element that moves between updates; a late push runs it out instead
/// of freezing the surface. It sweeps under Reduce Motion deliberately: it is
/// progress indication, and in the minimal presentation the only phase signal.
struct BreathCue: View {
    let presence: SessionPresence
    let accent: Color

    /// The ring's frame. The cue lays out at this size in every state, so a
    /// phase change never moves anything beside it.
    let diameter: CGFloat

    /// The resting ring's weight, as a fraction of the frame — 2.5 points at
    /// the compact 20, and heavier as the cue grows. Fixed, it drew a hairline
    /// at the expanded size where the swept ring it stands in for is thick, so
    /// the weight jumped at every pause.
    private static let restingWeight: CGFloat = 0.125

    var body: some View {
        Group {
            if let window = presence.window {
                // The system's own timer ring, which fills across the phase
                // with no update from the app at all.
                ProgressView(
                    timerInterval: window,
                    countsDown: presence.breath.cueCountsDown
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(tint)
            } else {
                // A plain resting ring wherever there is no window to sweep,
                // so the layout is the same shape in every state.
                Circle().stroke(tint.opacity(0.3), lineWidth: diameter * Self.restingWeight)
            }
        }
        .frame(width: diameter, height: diameter)
        // Every presentation that draws this labels the element around it with
        // the spoken instruction; the drawn ring is a picture of that sentence.
        .accessibilityHidden(true)
    }

    /// The shared hold-shift — `SessionPresence.cueTint(over:)` says why a
    /// paused ring may not wear the hold's colour.
    private var tint: Color {
        presence.cueTint(over: accent)
    }
}
