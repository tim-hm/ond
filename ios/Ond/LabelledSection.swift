import OndUI
import SwiftUI

/// A heading and whatever sits under it, at the spacing the scrolling screens
/// hold.
///
/// Two screens stack named sections down a `ScrollView` — Home and the Protocols
/// list — and each had written the same heading font, weight and gap into a
/// private helper. Neither is a `List`, so there is no `Section` to inherit the
/// platform's answer from, which is exactly the case where two hand-written
/// copies quietly drift a point apart.
///
/// App-local rather than in `OndUI` because it is a layout convention of these
/// two screens, not a component of the design system: nothing outside this
/// target draws one, and the escalation rule says a thing goes no further than
/// its consumers.
struct LabelledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(title)
                .font(.title3.weight(.semibold))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
