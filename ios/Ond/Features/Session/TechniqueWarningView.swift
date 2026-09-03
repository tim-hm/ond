import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One session's safety note, standing between Begin and the countdown.
/// Onboarding's consent names the hazards every exercise shares; this
/// interrupts only sessions carrying a hazard of their own, keeping the
/// warning off the breathing screen. Left unticked it returns next session;
/// ticked, it stays away until the note's wording changes. "Not now" declines.
struct TechniqueWarningView: View {
    let warning: SessionWarning
    /// Called with whether the tick was down. Recording the acceptance is the
    /// caller's, which keeps this screen pure presentation: one output per
    /// answer, no store to thread in.
    let onAccepted: (_ silenced: Bool) -> Void
    /// Called for "Not now", which declines the session, not just the warning.
    let onDeclined: () -> Void

    @State private var silence = false

    /// A scroll view like the consent screen's, not the invitation's centred
    /// stack: at accessibility type sizes the note outgrows the screen, and a
    /// warning whose tail truncates behind its own Accept button is a fainting
    /// hazard somebody agreed to unread.
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.standard) {
                Text(warning.heading)
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)

                Text(warning.text)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.loose)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.close) {
                Button {
                    silence.toggle()
                } label: {
                    Label(
                        SessionWarning.silence,
                        systemImage: silence ? "checkmark.square.fill" : "square"
                    )
                    .font(.subheadline)
                }
                .tapTarget()
                // A toggle with a spoken state, not a glyph swap VoiceOver
                // stays silent about: an unnoticed tick here silences a
                // fainting warning until its wording changes.
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(silence ? "On" : "Off")

                Button(SessionWarning.acceptance) {
                    onAccepted(silence)
                }
                .buttonStyle(.capsuleAction(Theme.Accent.brand))

                Button(SessionWarning.refusal) {
                    onDeclined()
                }
                .font(.subheadline)
                .tapTarget()
            }
            .padding(.horizontal, Theme.Spacing.loose)
            .padding(.top, Theme.Spacing.close)
        }
        // The invitation's reasoning, inherited with its palette: primary is
        // the only ink that clears AA over the accent wash this screen sits on.
        .foregroundStyle(Theme.Ink.primary)
    }
}
