import OndKit
import OndUI
import SwiftUI

/// The four switches and the reminder dial, asked once instead of found later.
///
/// Every label here is Settings' own, word for word. They are the same
/// switches — this screen writes to the same stores — and somebody who turns
/// one on here and goes looking for it afterwards has to find the row they
/// remember rather than a paraphrase of it.
///
/// Leaving this screen asks iOS for every permission the switches left on
/// imply, and for nothing they are off for. A switch somebody has just turned
/// on *is* the in-context ask Apple's guidance is about, and a system sheet a
/// week later, at some moment they have forgotten this screen, is the one that
/// arrives without a reason attached. See [`OnboardingModel/requestOptInGrants()`].
struct OptInsStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(
            title: "Permissions",
            subtitle: "Change options later in Settings."
        ) {
            switches
            reminders
        }
    }

    /// One card holding all four, rather than four cards: they are a single
    /// question — how much may this app do on your behalf — and four slabs of
    /// glass would read as four decisions to make.
    ///
    /// The two rows that name önd+ say so under the label rather than dimming.
    /// The trial is the next screen, so a switch disabled here would be turned
    /// off for somebody about to be able to use it; and the preference is
    /// theirs either way, which is exactly the argument Settings makes for
    /// never locking the off direction.
    private var switches: some View {
        VStack(spacing: Theme.Spacing.standard) {
            row("Ask how you feel before and after", isOn: $model.optIns.asksHowYouFeel)
            row(
                "Heart rate from your Apple Watch",
                note: "Needs önd+",
                isOn: $model.optIns.showsWristPulse
            )
            row(
                "Read my heart data",
                note: "Needs önd+",
                isOn: $model.optIns.coachReadsHealthTrends
            )
            row("Write Mindful Minutes to Health", isOn: $model.optIns.writesMindfulMinutes)
        }
        .padding(Theme.Spacing.standard)
        .glassCard()
    }

    private func row(_ title: String, note: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.Ink.primary)

                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
        }
        .tint(Theme.Accent.brand)
    }

    /// The dial, as a row rather than the screen of cards it used to be.
    ///
    /// It arrives on `Once a day` rather than on `Never`: a reminder is what
    /// makes a breathing app a practice rather than a thing installed once, and
    /// the row states its own position, so the default is a proposal somebody
    /// can see and decline rather than a setting slipped past them.
    private var reminders: some View {
        OnboardingPickerRow("Remind me", selection: $model.reminderIntensity) {
            ForEach(ReminderIntensity.allCases) { intensity in
                Text(intensity.title).tag(intensity)
            }
        }
    }
}
