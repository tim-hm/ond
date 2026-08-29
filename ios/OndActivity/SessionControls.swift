import AppIntents
import OndKit
import OndUI
import SwiftUI

/// What the session is waiting to be asked, and the way out, without
/// unlocking anything. Two buttons, never three: End keeps its own and
/// everything else shares one — a session is only ever on one side of that
/// question, and neither host (the expanded Island, the lock screen card)
/// has the height for more.
struct SessionControls: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            primary
            control(EndSessionIntent(), title: "End", isSecondary: true)
        }
    }

    /// The one control that changes with the session — or, for a paused
    /// session that cannot follow the person out of the app, none: resuming
    /// out here would start a plan the system suspends a second later, so the
    /// Island offers only the way out and the paused notice says where to
    /// carry on. A retention takes "I'm ready", the in-app hold's own words.
    @ViewBuilder
    private var primary: some View {
        if presence.isHolding {
            control(ReleaseHoldIntent(), title: "I'm ready")
        } else if !presence.isPaused {
            control(PauseSessionIntent(), title: "Pause")
        } else if attributes.followsYouOut {
            control(ResumeSessionIntent(), title: "Resume")
        }
    }

    /// One text control running `intent` in the app's process — the in-app
    /// transport pill at its host's width, where the word is clearer than an
    /// icon. `LiveActivityIntent` runs where the session is, not in this
    /// extension; new intents belong in `Intents/`, the one directory the app
    /// target compiles too — anywhere else draws a button that does nothing.
    private func control(
        _ intent: some LiveActivityIntent,
        title: String,
        isSecondary: Bool = false
    ) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSecondary ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minimumTapTarget)
        .contentShape(.rect)
    }
}
