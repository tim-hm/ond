import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Everything the app asks about the person, on one screen: what to call them,
/// what brought them here, and how much they want explained.
///
/// Three questions where there used to be three screens, and none of them is
/// required — the name is a greeting, the goals decide what is shown first, and
/// the experience level only chooses how much a session narrates. Skip takes
/// all three unanswered, and every one of them is editable in Settings
/// afterwards.
struct YouStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(
            title: "A little about you",
            subtitle: "None of this is required."
        ) {
            name
            goals
            experience
        }
    }

    /// The one field in the flow somebody types into.
    ///
    /// The placeholder is the whole label, which works because the question is
    /// four words and the answer is a word: a heading above an empty field
    /// would be the same sentence twice. VoiceOver reads the placeholder as the
    /// field's label, so it is not lost with the hint.
    private var name: some View {
        TextField("What should we call you?", text: $model.givenName)
            .font(.body)
            .foregroundStyle(Theme.Ink.primary)
            // A given name, so iOS offers the one on the device rather than
            // treating this as a new credential to save.
            .textContentType(.givenName)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(Theme.Spacing.standard)
            .glassCard()
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            heading("What brings you here?", detail: "Pick as many as you like.")

            ForEach(TechniqueGoal.allCases, id: \.self) { goal in
                OnboardingChoice(
                    title: goal.title,
                    detail: nil,
                    isSelected: model.isSelected(goal),
                    accent: goal.accent
                ) {
                    model.toggle(goal)
                }
            }
        }
    }

    /// One row rather than the three full-width cards this used to be.
    ///
    /// It is the least consequential answer on the screen — every exercise is
    /// available at every level, and all it decides is how much a session
    /// explains — so it takes the least room, and nothing underneath narrates
    /// what the choice will do. The row states the question and the answer,
    /// which between them are the whole control.
    private var experience: some View {
        OnboardingPickerRow("Done this before?", selection: $model.experienceLevel) {
            OptionalPickerOptions<ExperienceLevel>()
        }
    }

    /// A question inside the step, under the step's own heading — smaller than
    /// the title above it, so the screen reads as one page with parts rather
    /// than as three headings competing.
    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, Theme.Spacing.close)
    }
}
