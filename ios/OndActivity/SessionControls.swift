import AppIntents
import OndKit
import OndUI
import SwiftUI

/// What the session is waiting to be asked, and the way out of it, without
/// unlocking anything.
///
/// Two buttons, never three: End keeps its own and everything else shares one,
/// because a session is only ever on one side of the question those answer and a
/// lock screen glanced at mid-breath has no room to say otherwise.
struct SessionControls: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            primary
            control(EndSessionIntent(), icon: "stop.fill", named: "End")
        }
    }

    /// The one control that changes with the session — and, in one case, is not
    /// drawn at all.
    ///
    /// A retention takes "I'm ready", the same words the in-app hold uses, since
    /// nothing else can advance it. A session that cannot follow the person out
    /// of the app takes nothing: resuming it out here would start a plan the
    /// system suspends a second later, so the honest lock screen offers only the
    /// way out and the paused notice says where to carry on.
    @ViewBuilder
    private var primary: some View {
        if presence.isHolding {
            control(ReleaseHoldIntent(), icon: "checkmark", named: "I'm ready")
        } else if !presence.isPaused {
            control(PauseSessionIntent(), icon: "pause.fill", named: "Pause")
        } else if attributes.followsYouOut {
            control(ResumeSessionIntent(), icon: "play.fill", named: "Resume")
        }
    }

    /// One round control running `intent` in the app's process.
    ///
    /// - Parameters:
    ///   - intent: what the press does. A `LiveActivityIntent` rather than a
    ///     plain one, so it runs where the session is rather than in this
    ///     extension, which can reach nothing.
    ///   - icon: the SF Symbol on the face of it.
    ///   - named: what VoiceOver says. The button is an icon and has no text of
    ///     its own to fall back on.
    private func control(
        _ intent: some LiveActivityIntent,
        icon: String,
        named name: String
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(accent)
        .accessibilityLabel(name)
    }
}
