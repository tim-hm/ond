import OndUI
import SwiftUI

/// Keeps a setting's title and selected value in distinct columns until an
/// accessibility text size needs them to take separate lines.
@ViewBuilder
func settingsPicker(
    _ title: String,
    description: String? = nil,
    selection: Binding<some Hashable>,
    stacks: Bool,
    @ViewBuilder content: () -> some View
) -> some View {
    if stacks {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            settingsLabel(title, description: description)
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    } else if let description {
        HStack(alignment: .center, spacing: Theme.Spacing.standard) {
            settingsLabel(title, description: description)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(title). \(description)")
        }
    } else {
        Picker(title, selection: selection, content: content)
    }
}

/// A setting's title and the immediate consequence of changing it.
func settingsLabel(_ title: String, description: String?) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
        Text(title)
            .foregroundStyle(Theme.Ink.primary)
        if let description {
            Text(description)
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
