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
/// Nothing on this screen asks iOS for anything, which is the footer's promise
/// and the reason the flow has an `applyOptIns` at all: a Health sheet raised
/// over a page of switches asks somebody to decide about data before the app
/// has given them a reason to share any. The permission each of these implies
/// is asked at the first genuine use of the thing it governs.
struct OptInsStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(
            title: "How should we behave?",
            subtitle: "Every one of these is off in Settings later if you change your mind."
        ) {
            switches
            reminders

            Text("Nothing here summons a system prompt. Health is asked the first "
                + "time a session or your coach actually needs it, and if you pick "
                + "a nudge, iOS asks about notifications once you're through.")
                .font(.footnote)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.top, Theme.Spacing.close)
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
                "Share watch trends",
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
    /// `Never` is first in `ReminderIntensity.allCases` and is already selected,
    /// so leaving this alone is the silent answer — the whole privacy stance
    /// here rests on the default rather than on anybody making a choice.
    private var reminders: some View {
        HStack {
            Text("Remind me")
                .font(.body)
                .foregroundStyle(Theme.Ink.primary)
                // The Picker announces the same label; a second copy would make
                // VoiceOver say it twice.
                .accessibilityHidden(true)

            Spacer()

            Picker("Remind me", selection: $model.reminderIntensity) {
                ForEach(ReminderIntensity.allCases) { intensity in
                    Text(intensity.title).tag(intensity)
                }
            }
            .labelsHidden()
            .tint(Theme.Ink.secondary)
        }
        .padding(.vertical, Theme.Spacing.close)
        .padding(.horizontal, Theme.Spacing.standard)
        .glassCard()
    }
}
