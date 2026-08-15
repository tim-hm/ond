import OndKit
import OndUI
import SwiftUI

/// A server refusal before either profile form's editable fields.
///
/// Leading placement keeps the verdict ahead of the answers it rejected in
/// both visual and VoiceOver order.
struct ProfileRefusalSection: View {
    let reason: String?

    var body: some View {
        if let reason {
            Section {
                Text(reason)
                    .foregroundStyle(Theme.Accent.caution)
            } header: {
                Text("Not saved")
            }
            .listRowBackground(Theme.Surface.raised)
        }
    }
}

/// Saves either profile form, dismissing only when the server did not refuse
/// the submitted answers.
struct ProfileSaveButton: View {
    let model: ProfileEditModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Save") {
            Task {
                await model.save()
                if model.rejection == nil {
                    dismiss()
                }
            }
        }
        .disabled(!model.canSave)
    }
}
