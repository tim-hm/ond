import OndKit
import OndUI
import SwiftUI

/// The whole of the leaderboard opt-in: type a name and you are on the
/// boards; clear it and you are not — the server lists only profiles that
/// carry a name, and it never invents one. The fields are also editable under
/// Settings, both driving the same `ProfileEditModel`, so the rule behind the
/// field is not duplicated. A generated name is offered, never filled in.
struct LeaderboardNameView: View {
    @State private var model: ProfileEditModel

    /// A name on offer, for somebody who does not want to invent one. Offered
    /// rather than filled in: an empty field is how a person says "not on the
    /// boards", so arriving with a name already typed would opt them in by
    /// default. One tap adopts it; the arrow beside it deals another.
    @State private var offered = LeaderboardNameGenerator.name()

    init(profiles: ProfileStore) {
        _model = State(wrappedValue: ProfileEditModel(store: profiles))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            ProfileRefusalSection(reason: model.rejection)

            Section {
                TextField("Name", text: $model.draft.displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                // Only while there is nothing to lose. Offering a fresh name
                // over one somebody typed would be a control whose best outcome
                // is that they ignore it.
                if model.draft.displayName.isEmpty {
                    suggestion
                }
            } header: {
                Text("Display name")
            } footer: {
                Text(
                    "This is the only thing other people see. Your goals, notes and history "
                        + "stay private. "
                        + "Leave it empty and you stay invisible on every board while still "
                        + "seeing your own place. If somebody already has the name, we'll add a "
                        + "number to yours."
                )
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Born", selection: $model.draft.birthYearBand) {
                    OptionalPickerOptions<BirthYearBand>()
                }
            } footer: {
                Text(
                    "Optional. It decides which decade's board you can compare within, "
                        + "and lets your coach read a breath-test score against the right "
                        + "baseline. It is not used anywhere else."
                )
            }
            .listRowBackground(Theme.Surface.raised)
        }
        .paletteGround()
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ProfileSaveButton(model: model)
            }
        }
    }

    /// The offered name, and the two things you can do with it.
    ///
    /// The name is a button rather than a label with a button beside it: the
    /// thing somebody wants to press is the name, and a "Use this" alongside
    /// would be a second control for the same tap.
    private var suggestion: some View {
        @Bindable var model = model

        return HStack {
            Button {
                model.draft.displayName = offered
            } label: {
                Text(offered)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use the name \(offered)")

            Button {
                offered = LeaderboardNameGenerator.name()
            } label: {
                Image(systemName: "arrow.trianglehead.clockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Offer a different name")
        }
    }
}
