import AppIntents
import OndKit
import OndUI
import SwiftUI

/// Pause or resume, and end, without unlocking anything.
///
/// One button for pause and resume rather than two, because they are one
/// question and the session is only ever on one side of it — the same shape the
/// in-app control has. End keeps its own, and stays the quieter of the two:
/// a destructive control should be quieter than the breath it interrupts.
struct SessionControls: View {
    let presence: SessionPresence
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            if case .paused = presence.stance {
                control(ResumeSessionIntent(), icon: "play.fill", named: "Resume")
            } else {
                control(PauseSessionIntent(), icon: "pause.fill", named: "Pause")
            }

            control(EndSessionIntent(), icon: "stop.fill", named: "End")
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
