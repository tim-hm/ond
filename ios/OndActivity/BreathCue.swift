import OndKit
import OndStyle
import SwiftUI

/// The minimal presentation's cue: a ring that sweeps the phase it is in, in
/// the phase's colour.
///
/// The one region the shared glyph did not take. Minimal is a lone circle with
/// no second element beside it — no count, no word — and a static dot alone
/// says nothing about time, so the sweeping ring stays: the system
/// interpolates it locally from the phase's own window, keeping pace whether
/// or not the next update lands on time, and degrading to a completed ring,
/// which still reads as the phase running out. *Which* phase is carried by the
/// sweep's direction — the ring fills as the lungs do and drains with them —
/// and the colour, which goes slate for a hold.
///
/// The ring sweeps under Reduce Motion too, deliberately: a timer ring is
/// progress indication rather than decorative motion, and here it is the only
/// phase signal there is. The same call the in-app guide makes when it keeps
/// its phase fill moving while the glyph stands still.
struct BreathCue: View {
    let presence: SessionPresence
    let accent: Color

    /// The ring's diameter — minimal's own square, the one place this draws.
    /// The cue lays out at this size in every state, so a phase change never
    /// moves anything beside it.
    private static let diameter: CGFloat = 20
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
        .frame(width: Self.diameter, height: Self.diameter)
        // The minimal presentation labels the cue itself with the spoken
        // instruction; the drawn ring is a picture of that sentence.
        .accessibilityHidden(true)
    }

    /// The shared hold-shift — `SessionPresence.cueTint(over:)` says why a
    /// paused ring may not wear the hold's colour.
    private var tint: Color {
        presence.cueTint(over: accent)
    }
}
