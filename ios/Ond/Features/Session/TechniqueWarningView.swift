import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One technique's safety note, standing between Begin and the countdown.
///
/// The second half of the app's safety copy, and deliberately not part of the
/// player: onboarding's consent screen names the hazards every exercise shares,
/// and this one interrupts only the sessions that carry a hazard of their own —
/// which keeps the warning out of the breathing screen itself and makes
/// accepting it an act, not a line of small print under an orb.
///
/// The tick is the person's, never the app's: left unticked, the warning comes
/// back next session; ticked, it stays away until the note's wording changes.
/// "Not now" is as honest an answer as accepting — someone given pause by a
/// fainting warning should have a way out that is not the risk.
struct TechniqueWarningView: View {
    let technique: Technique
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
                Text("Before \(technique.name)")
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)

                if let note = technique.safetyNote {
                    Text(note)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
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
                        "Don't show this again",
                        systemImage: silence ? "checkmark.square.fill" : "square"
                    )
                    .font(.subheadline)
                }
                .frame(minHeight: 44)
                // A toggle with a spoken state, not a glyph swap VoiceOver
                // stays silent about: an unnoticed tick here silences a
                // fainting warning until its wording changes.
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(silence ? "On" : "Off")

                Button("I understand") {
                    onAccepted(silence)
                }
                .capsuleAction(technique.goal.accent)

                Button("Not now") {
                    onDeclined()
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.Spacing.loose)
            .padding(.top, Theme.Spacing.close)
        }
        // The invitation's reasoning, inherited with its palette: primary is
        // the only ink that clears AA over the accent wash this screen sits on.
        .foregroundStyle(Theme.Ink.primary)
    }
}
