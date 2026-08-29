import AppIntents
import OndKit
import OndUI
import SwiftUI

/// What the session is waiting to be asked, and the way out of it, without
/// unlocking anything.
///
/// Two buttons, never three: End keeps its own and everything else shares one,
/// because a session is only ever on one side of the question those answer, and
/// neither host this draws in — the expanded Island, the lock screen card — has
/// the height to say otherwise.
struct SessionControls: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            primary
            control(EndSessionIntent(), title: "End", isSecondary: true)
        }
    }

    /// The one control that changes with the session — and, in one case, is not
    /// drawn at all.
    ///
    /// A retention takes "I'm ready", the same words the in-app hold uses, since
    /// nothing else can advance it. A session that cannot follow the person out
    /// of the app takes nothing: resuming it out here would start a plan the
    /// system suspends a second later, so the honest Island offers only the way
    /// out and the paused notice says where to carry on.
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
    /// icon with an accessibility-only name.
    ///
    /// - Parameters:
    ///   - intent: what the press does. A `LiveActivityIntent` rather than a
    ///     plain one, so it runs where the session is rather than in this
    ///     extension, which can reach nothing. New intents belong in
    ///     `Intents/`, the one directory the app target compiles too — an
    ///     intent anywhere else draws a button that does nothing on a device.
    ///   - title: the control's visible and spoken name.
    ///   - isSecondary: whether the control takes the quieter transport ink.
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
