import OndKit
import SwiftUI

/// Why somebody is looking at the paywall.
///
/// The surface that presented it knows what the person just ran into, and that
/// is the only thing this decides: the headline. Everything below it — the
/// benefits, price and trial — is the same offer however somebody arrived,
/// because there is one subscription and it is not sold in pieces.
///
/// A dedicated enum rather than the tier it replaced. With two paid tiers a
/// `SubscriptionTier` said which of them to lead with, and that question no
/// longer exists; passing a tier now would let a caller ask for `.free`, which
/// means nothing, and say nothing about what they were reaching for.
enum PaywallContext: Sendable, Equatable {
    /// The Coach tab, a coach door on a technique, or the suggestion strip.
    case coach
    /// A leaderboard, on the phone or behind its door.
    case leaderboards
    /// The health trends the coach reads, and the switch that turns them on.
    case health
    /// Anything that needs the wrist and the phone working together.
    case watch
    /// Settings, and anywhere else nobody ran into a wall to get here.
    case general

    /// Names what they came for rather than what is for sale.
    var headline: String {
        switch self {
        case .coach: "A coach grounded in your practice"
        case .leaderboards: "See where you stand"
        case .health: "Your practice, in context"
        case .watch: "Phone and Watch, together"
        case .general: "More from your practice"
        }
    }

    /// What would open the thing they ran into, read from the named lever
    /// rather than written as a rung.
    ///
    /// The levers are the point of `SubscriptionTier`'s design — one line per
    /// feature, and every gate a comparison against it — and a `.plus` typed
    /// into the paywall would be the one place that stopped honouring them: a
    /// feature repriced at its lever would still be offered, and dismissed,
    /// against a tier nothing had reconsidered.
    var requires: SubscriptionTier {
        switch self {
        case .coach: .assistant
        case .leaderboards: .leaderboards
        case .health: .healthTrends
        case .watch: .watchConnected
        // Nobody ran into a wall to get here, so the answer is the cheapest
        // thing that is not free — which, with one paid tier, is the tier.
        case .general: .plus
        }
    }
}

extension SubscriptionTier {
    /// What this tier is called in the interface.
    ///
    /// One mapping for the whole feature. The paywall's card and Settings' plan
    /// row used to answer this separately, which is how "Plus" and "önd Plus"
    /// end up on two screens describing the same thing. The paid name carries
    /// its brand because it is the product's name — there is no unbranded way
    /// to say it.
    var title: String {
        switch self {
        case .free: "Free"
        case .plus: "önd+"
        }
    }
}

extension View {
    /// Presents the paywall, opened on the headline that answers whatever the
    /// person just ran into.
    ///
    /// A modifier rather than a `.sheet` at each site: half a dozen screens
    /// offer the subscription, and six copies of the presentation are six
    /// chances to lose the sheet or lead with the wrong sentence.
    func paywall(for context: PaywallContext, isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(context)
        }
    }
}
