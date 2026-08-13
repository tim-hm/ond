import OndKit
import OndUI
import SwiftUI

/// The whole of the leaderboard opt-in: type a name and you are on them; clear
/// it and you are not.
///
/// Said plainly rather than as a toggle labelled "privacy", because that is
/// literally how it works — the server lists only profiles that carry a name,
/// and it never invents one.
///
/// The two fields it shows are also editable under Settings' profile screen, and
/// both drive the same `ProfileEditModel`. Two entry points rather than one
/// because the reason to type a name is the board you are looking at, and this
/// is where that reason can be stated; what must not be duplicated is the rule
/// behind the field, and it is not.
///
/// It also offers one. "What do I want strangers to call me" is a worse thing to
/// meet than a name already in the field, so `LeaderboardNameGenerator` deals
/// one — but into a control rather than into the field, because the field being
/// empty is the opt-out and nothing here may make that decision for somebody.
struct LeaderboardNameView: View {
    @State private var model: ProfileEditModel
    @Environment(\.dismiss) private var dismiss

    /// A name on offer, for somebody who does not want to invent one.
    ///
    /// Offered rather than filled in, and that is the whole of the design here:
    /// an empty field is how a person says "not on the boards", so a screen that
    /// arrived with a name already typed would opt them in by default and the
    /// footer beneath it would be lying. One tap adopts it; the arrow beside it
    /// deals another.
    @State private var offered = LeaderboardNameGenerator.name()

    init(profiles: ProfileStore) {
        _model = State(wrappedValue: ProfileEditModel(store: profiles))
    }

    var body: some View {
        @Bindable var model = model

        Form {
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
                if let rejection = model.rejection {
                    Text(rejection)
                        .foregroundStyle(Theme.Accent.caution)
                } else {
                    Text(
                        "This is the only thing other people see — no goals, no notes, no history. "
                            + "Leave it empty and you stay invisible on every board while still "
                            + "seeing your own place. If somebody already has the name, we'll add a "
                            + "number to yours."
                    )
                }
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Born", selection: $model.draft.birthYearBand) {
                    Text("Rather not say").tag(BirthYearBand?.none)
                    ForEach(BirthYearBand.allCases) { band in
                        Text(band.title).tag(BirthYearBand?.some(band))
                    }
                }
            } footer: {
                Text(
                    "Optional. It decides which decade's board you can compare within, "
                        + "and lets your coach read a breath-test score against the right "
                        + "baseline — nothing else."
                )
            }
            .listRowBackground(Theme.Surface.raised)
        }
        .paletteGround()
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await model.save()
                        // A refusal keeps the screen up. Dismissing over it would
                        // put the message somewhere nobody is looking, and leave
                        // a name that will never reach a board reading as saved.
                        if model.rejection == nil {
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canSave)
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
