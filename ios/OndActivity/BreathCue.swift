import OndKit
import OndUI
import SwiftUI

/// The whole cue: a ring that sweeps the phase it is in, in the phase's colour.
///
/// The system interpolates the sweep locally from the phase's own window, so it
/// keeps pace whether or not the next update lands on time. A cue built on
/// updates alone appears to work in the simulator and then falls behind on a
/// device; this one degrades to a completed ring, which still reads as the
/// phase running out. *Which* phase is carried three ways: the sweep's
/// direction — the ring fills as the lungs do and drains with them — the
/// colour, which goes slate for a hold, and the word every surface bar the
/// Island's minimal presentation pairs the ring with.
///
/// The ring sweeps under Reduce Motion too, deliberately: a timer ring is
/// progress indication rather than decorative motion, and in the minimal
/// presentation it is the only phase signal there is. The same call the in-app
/// guide makes when it keeps its phase fill moving while the orb stands still.
///
/// Deliberately the smallest geometry that can carry a breath. TIM-129's figure
/// grows out of this rather than replacing it, so anything here that is not a
/// circle and a fraction is something that would have to be torn out.
struct BreathCue: View {
    let presence: SessionPresence
    let accent: Color
    /// The ring's diameter. The cue lays out at this size in every state, so a
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
                    countsDown: presence.breath.kind == .exhale
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
        // A picture of what the words beside it say. Every surface that shows
        // this also shows those, bar the Island's minimal presentation, which
        // labels the cue itself.
        .accessibilityHidden(true)
    }

    /// The hold's indigo while a breath is held, the goal's accent otherwise —
    /// the same shift the in-app orb makes, so the Island and the screen mark a
    /// hold the same way. Not while paused, though: the words beside the ring
    /// say "Paused" rather than naming the phase, and a hold-coloured ring
    /// would go on asserting a hold nobody is in.
    private var tint: Color {
        presence.breath.kind.isHold && !presence.isPaused ? Theme.Breath.hold : accent
    }
}
