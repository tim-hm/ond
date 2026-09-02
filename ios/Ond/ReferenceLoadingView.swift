import OndUI
import SwiftUI

/// The phone's waiting state, in the ground and the vocabulary
/// `ReferenceRetryView` set. No spinner, for the reason `HealthTrendsCard`
/// states: a spinner that flashes for a frame is noise rather than news, and
/// the wait ends either way — the request carries a deadline, after which the
/// retry view says so. Nothing moves, so Reduce Motion needs no branch.
struct ReferenceLoadingView: View {
    /// What the host has already drawn, which decides what is left to say.
    enum Scale {
        /// A screen body with no navigation title. The name is the heading.
        case screen
        /// A screen body under a navigation title, which is the heading.
        case titled
        /// A section inside a screen that draws other things around it.
        case inline
    }

    let scale: Scale

    init(_ scale: Scale = .screen) {
        self.scale = scale
    }

    var body: some View {
        switch scale {
        case .screen:
            VStack(spacing: Theme.Spacing.standard) {
                // Silent to VoiceOver: it is a heading that lasts a moment and
                // then gives way to the screen's own.
                Wordmark()
                    .accessibilityHidden(true)
                line
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .titled:
            line
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .inline:
            line
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.loose)
        }
    }

    private var line: some View {
        Text("Loading…")
            .font(.callout)
            .foregroundStyle(Theme.Ink.tertiary)
    }
}
