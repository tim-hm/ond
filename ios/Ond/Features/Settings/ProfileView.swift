import OndKit
import OndUI
import SwiftUI

/// Everything somebody told the app about themselves, in one place they can
/// change it.
///
/// Onboarding asked these questions once and then never again, which was the
/// whole problem: the reason a person started breathing is the thing most likely
/// to have moved on by the time they notice the app still answering the old one.
/// The sections keep onboarding's order so a returning reader recognises the
/// questions rather than meeting them rearranged.
///
/// One Save rather than a write per row, because the profile goes over the wire
/// as a wholesale replacement and the server may hand back something other than
/// what was sent — a taken display name comes back suffixed. A row that saved on
/// change would have to explain that mid-scroll, five times over.
///
/// The reminder dial is the exception, and it is not on this screen: it is
/// stored on the profile but it is not a fact about the person, and it now sits
/// under Reminders in Settings beside the schedules it reshapes. See
/// `ReminderDial` for why it writes through instead of waiting for a Save.
struct ProfileView: View {
    @State private var model: ProfileEditModel

    init(profiles: ProfileStore) {
        _model = State(wrappedValue: ProfileEditModel(store: profiles))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            ProfileRefusalSection(reason: model.rejection)

            Section {
                TextField("Name", text: $model.draft.givenName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("What we call you")
            } footer: {
                Text("Onboarding asked for this, and this is where it changes — "
                    + "clear it and the app stops using it. Nobody else ever sees "
                    + "it; the leaderboard name at the bottom is the one they do.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                ForEach(TechniqueGoal.allCases, id: \.self) { goal in
                    goalRow(goal)
                }
            } header: {
                Text("What brings you here")
            } footer: {
                Text("Pick as many as you like. It decides what we show you "
                    + "first, and it is the first thing your coach reads.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Experience", selection: $model.draft.experienceLevel) {
                    OptionalPickerOptions<ExperienceLevel>()
                }
            } footer: {
                Text("Every exercise is available either way. It only sets how "
                    + "much your coach assumes you already know. What a session "
                    + "puts on screen is Guidance, back in Settings.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Born", selection: $model.draft.birthYearBand) {
                    OptionalPickerOptions<BirthYearBand>()
                }

                Picker("Gender", selection: $model.draft.gender) {
                    OptionalPickerOptions<Gender>()
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Your decade and gender let your coach read a breath-test "
                    + "score against the right baseline, and your decade decides "
                    + "which age-band leaderboard you can compare within. That's "
                    + "everything they're used for.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                TextField(
                    "Anything you'd like your coach to know?",
                    text: $model.draft.intentNote,
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
            } header: {
                Text("Note for your coach")
            } footer: {
                Text("Why you're here, in your own words. Nothing else reads it.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                TextField("Name", text: $model.draft.displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Display name")
            } footer: {
                Text("The only thing other people see on a leaderboard — no "
                    + "goals, no notes, no history. Empty means invisible, which "
                    + "is where every profile starts.")
            }
            .listRowBackground(Theme.Surface.raised)
        }
        .paletteGround()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ProfileSaveButton(model: model)
            }
        }
    }

    /// One goal as a tappable row.
    ///
    /// A checkmark rather than a `Toggle`, because the order they were picked in
    /// is carried to the coach: a column of switches reads as five independent
    /// settings, where a list you add to reads as an answer being built.
    private func goalRow(_ goal: TechniqueGoal) -> some View {
        Button {
            model.toggle(goal)
        } label: {
            LabeledContent(goal.title) {
                if model.isSelected(goal) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Accent.brand)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.isSelected(goal) ? [.isButton, .isSelected] : .isButton)
    }
}
