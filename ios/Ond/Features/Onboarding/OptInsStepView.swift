import OndKit
import OndUI
import SwiftUI

/// The four switches and the reminder dial, asked once instead of found
/// later. Every label is Settings' own, word for word — this screen writes to
/// the same stores. Leaving the screen asks iOS for the permissions the
/// switches left on need; a switch just turned on *is* the in-context ask.
/// See [`OnboardingModel/requestOptInGrants()`].
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

    /// One card holding all four: they are a single question — how much may
    /// this app do on your behalf. The two rows that name önd+ say so under
    /// the label rather than dimming: the trial is the next screen, so a
    /// switch disabled here would be off for somebody about to be able to use
    /// it, and Settings never locks the off direction either.
    private var switches: some View {
        VStack(spacing: Theme.Spacing.standard) {
            row("Mood before and after", isOn: $model.optIns.asksHowYouFeel)
            row(
                "Live heart rate",
                note: SubscriptionTier.plusRequirementNote,
                isOn: $model.optIns.showsWristPulse
            )
            row(
                "Heart and sleep data",
                note: SubscriptionTier.plusRequirementNote,
                isOn: $model.optIns.coachReadsHealthTrends
            )
            row("Mindful minutes", isOn: $model.optIns.writesMindfulMinutes)

            Divider()
                .overlay(Theme.Surface.line)
                .padding(.horizontal, -Theme.Spacing.standard)

            Text(
                "Next asks iOS for the permissions your switches need. "
                    + "Nothing is asked for a switch that is off."
            )
            .font(.caption)
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The dial arrives on `Once a day`, not `Never`: a reminder is what makes
    /// a breathing app a practice, and the row states its own position — a
    /// proposal somebody can see and decline, not a setting slipped past them.
    private var reminders: some View {
        OnboardingPickerRow("Remind me", selection: $model.reminderIntensity) {
            ForEach(ReminderIntensity.allCases) { intensity in
                Text(intensity.title).tag(intensity)
            }
        }
    }
}
