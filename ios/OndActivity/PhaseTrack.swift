import OndKit
import OndStyle
import SwiftUI

/// The phase running out, as a thin line the system sweeps locally with no
/// update from the app — the honest degradation: a late or dropped push runs
/// the track out rather than freezing the surface mid-phase. With no window
/// (a retention, a pause) a resting line keeps the height still. Hidden from
/// VoiceOver: a picture of what the words beside it already say.
struct PhaseTrack: View {
    let presence: SessionPresence
    let accent: Color

    var body: some View {
        Group {
            if let window = presence.window {
                ProgressView(
                    timerInterval: window,
                    countsDown: presence.breath.cueCountsDown
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(height: 3)
            } else {
                Capsule()
                    .fill(tint.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    /// The shared hold-shift — `SessionPresence.cueTint(over:)` says why a
    /// paused track may not wear the hold's colour.
    private var tint: Color {
        presence.cueTint(over: accent)
    }
}
