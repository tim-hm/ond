import OndKit
import OndUI
import SwiftUI

// The shell every card that starts a stop wears: one tappable region that
// begins the session, with the star beside it. It draws no material — the
// card draws its own glass, and glass under glass is the hazard — so it has
// opinions about padding and none about the surface. The spoken label lives
// here: a button's label replaces every label composed beneath it.

struct StartableStopCard<Content: View>: View {
    let stop: DialStop
    let tier: SubscriptionTier
    let start: () -> Void

    @ViewBuilder let content: () -> Content

    @Environment(StarredStopStore.self) private var stars

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.standard) {
            Button(action: start) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Inside the button, where the hit region is: on the row,
                    // this padding left a sixteen-point dead band above and
                    // below every title that answered to no tap.
                    .padding(.leading, Theme.Spacing.standard)
                    .padding(.vertical, Theme.Spacing.standard)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stop.spokenLabel(for: tier))
            .accessibilityHint("Starts the session")

            StopStarButton(stop: stop, isStarred: stars.isStarred(stop)) {
                stars.toggle(stop)
            }
            // The same inset the words take, so the star stays where it was
            // when the row wore this padding as a whole.
            .padding(.vertical, Theme.Spacing.standard)
        }
    }
}
