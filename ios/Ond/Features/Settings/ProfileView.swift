import OndKit
import OndUI
import SwiftUI

/// Everything somebody told the app about themselves, editable in one place.
/// One Save, not a write per row: the profile goes over the wire as a
/// wholesale replacement, and the server may answer with changes — a taken
/// display name comes back suffixed. The reminder dial lives under Reminders
/// in Settings instead; see `ReminderDial` for why it writes through.
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
                Text(
                    "Your first name personalises your home screen. It is not shown to other people."
                )
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
                    + "first.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Born", selection: $model.draft.birthYearBand) {
                    OptionalPickerOptions<BirthYearBand>()
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Your birth decade selects your optional age-band leaderboard.")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                TextField("Name", text: $model.draft.displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Display name")
            } footer: {
                Text("Other people see your display name and the value being ranked. "
                    + "Your other profile details are not shown on the board. "
                    + "Leave this empty to stay off the boards.")
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
