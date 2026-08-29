import OndUI
import SwiftUI

/// A heading and whatever sits under it, at the spacing the scrolling screens
/// hold.
///
/// Two screens stack named sections down a `ScrollView` — Progress and the
/// Exercises list — and each had written the same heading font, weight and
/// gap into a private helper. Neither is a `List`, so there is no `Section` to inherit the
/// platform's answer from, which is exactly the case where two hand-written
/// copies quietly drift a point apart.
///
/// App-local rather than in `OndUI` because it is a layout convention of these
/// two screens, not a component of the design system: nothing outside this
/// target draws one, and the escalation rule says a thing goes no further than
/// its consumers.
///
/// The heading is the spec's section header — 13 points, medium, tracked a
/// tenth of an em, uppercase, in the quietest ink — which is the refresh's argument
/// about section headings: a `.title3` over a card of the same weight competes
/// with the card's own title, where a small tracked line labels the group and
/// then gets out of the way. Not `.eyebrow()`, deliberately: that is the chip
/// role, a point smaller and semibold, and a group label set in it reads as
/// one more chip.
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
