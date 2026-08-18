import OndUI
import SwiftUI

/// The coach's offer of a breath-hold test as a card under its reply.
///
/// `OfferCard`'s shell and its bargain: the coach's prose stands on its own,
/// and the card is the one action that acts on it.
struct BoltTestOfferCard: View {
    let start: () -> Void

    var body: some View {
        OfferCard(
            eyebrow: "Check-in",
            title: "Comfortable pause",
            // The check-in screen's own words for it, so the card and the door
            // it leads to describe the same two minutes.
            summary: "A two-minute check-in on your breathing.",
            // Focus, which is what a controlled pause asks for — the one offer
            // here that names no exercise and so has no goal to borrow.
            goal: .focus
        ) {
            Button("Take it", action: start)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Ink.primary)
                .foregroundStyle(Theme.Surface.ground)
        }
    }
}
