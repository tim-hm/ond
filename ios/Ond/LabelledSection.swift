import OndUI
import SwiftUI

/// A heading and whatever sits under it, at the spacing the scrolling screens
/// hold. Progress and the Exercises list are `ScrollView`s with no `Section`
/// to inherit from, and their hand-written copies drifted apart. Not
/// `.eyebrow()`: that is the chip role. One action may sit on the heading,
/// which is the only line a section owns outright.
struct LabelledSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    /// At accessibility sizes the heading takes the width by itself, so the
    /// action drops below it rather than squeezing both onto one line.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            heading
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var heading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                label
                accessory()
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
                label
                Spacer(minLength: 0)
                accessory()
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Ink.tertiary)
    }
}

extension LabelledSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}
