import OndUI
import SwiftUI

/// A heading and whatever sits under it, at the spacing the scrolling
/// screens hold. Progress and the Exercises list are `ScrollView`s with no
/// `Section` to inherit from, and their hand-written copies drifted apart.
/// The heading is the spec's section header — small, tracked, uppercase, in
/// quiet ink. Not `.eyebrow()`: that is the chip role and reads as a chip.
struct LabelledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(title)
                .font(.footnote.weight(.medium))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Ink.tertiary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
