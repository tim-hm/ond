import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The phase running out, as a thin line the system sweeps locally with no
/// update from the app — the honest degradation: a late or dropped push runs
/// the track out rather than freezing the surface mid-phase. With no window
/// (a retention, a pause) a resting line keeps the height still. Hidden from
/// VoiceOver: a picture of what the words beside it already say.
struct PhaseTrack: View {
    let presence: SessionPresence

    /// §8's own pair. The fill does not take the hold's colour the way the
    /// glyph beside it does: this is the phase running out, and it runs out
    /// at the same rate whichever phase it is.
    private static let track = Theme.Ink.primary.opacity(0.18)
    private static let height: CGFloat = 3

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
                .tint(Theme.Breath.inhale)
                .background(Capsule().fill(Self.track))
            } else {
                Capsule()
                    .fill(Self.track)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}
