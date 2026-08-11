import OndUI
import SwiftUI

/// The coach's offer of a breath-hold test as a card under its reply.
///
/// `ExerciseOfferCard`'s shape and its bargain: the coach's prose stands on its
/// own, and the card is the one action that acts on it. Carries no summary line
/// because there is nothing to summarise — the offer is the whole payload, and a
/// caption restating the button would be the card talking to itself.
struct BoltTestOfferCard: View {
    let start: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.standard) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Comfortable pause")
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)
                // The check-in screen's own words for it, so the card and the
                // door it leads to describe the same two minutes.
                Text("A two-minute check-in on your breathing.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Take it", action: start)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Accent.brand)
        }
        .padding(Theme.Spacing.standard)
        .glassCard()
    }
}
