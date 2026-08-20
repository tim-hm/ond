import OndKit
import OndStyle
import SwiftUI

/// The Island's breath cue: a ring that sweeps the phase it is in, in the
/// phase's colour.
///
/// A widget steps between snapshots rather than animating through them, so
/// anything drawn from the payload alone shows one still frame per phase — two
/// sizes across a breath, and nothing in between. A timer ring is the way out:
/// the system interpolates it locally from the phase's own window, so it keeps
/// pace whether or not the next update lands on time, and degrades to a
/// completed ring, which still reads as the phase running out.
///
/// *Which* phase is carried by the sweep's direction — the ring fills as the
/// lungs do and drains with them — and by the colour, which goes indigo for a
/// hold.
///
/// The ring sweeps under Reduce Motion too, deliberately: a timer ring is
/// progress indication rather than decorative motion, and in the minimal
/// presentation it is the only phase signal there is. The same call the in-app
/// guide makes when it keeps its phase fill moving while the glyph stands
/// still.
struct BreathCue: View {
    let presence: SessionPresence
    let accent: Color

    /// The ring's frame. The cue lays out at this size in every state, so a
    /// phase change never moves anything beside it.
    let diameter: CGFloat

    private static let restingRing: CGFloat = 2.5

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
                Circle().stroke(tint.opacity(0.3), lineWidth: Self.restingRing)
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
