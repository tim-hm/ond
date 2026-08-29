import OndUI
import SwiftUI

/// One question as a compact row: a label on the left, a menu on the right,
/// and the glass under both. Shared down to the VoiceOver detail: the
/// `Picker` announces the label itself, so the `Text` beside it has to be
/// hidden or every row is read twice.
struct OnboardingPickerRow<Selection: Hashable, Options: View>: View {
    /// Shown, and given to the `Picker` as its own label so assistive
    /// technology names the control rather than reading a bare value.
    private let title: String
    @Binding private var selection: Selection
    /// The rows of the menu, tagged with `Selection` values.
    private let options: Options

    init(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityHidden(true)

            Spacer()

            Picker(title, selection: $selection) {
                options
            }
            .labelsHidden()
            .tint(Theme.Ink.secondary)
        }
        .padding(.vertical, Theme.Spacing.close)
        .padding(.horizontal, Theme.Spacing.standard)
        .glassCard()
    }
}
