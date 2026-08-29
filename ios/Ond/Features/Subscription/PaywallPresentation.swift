import OndKit
import SwiftUI

/// Why somebody is looking at the paywall. The presenting surface knows what
/// the person ran into, and that decides which entitlement dismisses the
/// sheet; the visible pitch stays identical because there is one subscription.
/// A dedicated enum rather than a `SubscriptionTier`, which would let a
/// caller pass `.free` — a context that means nothing.
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

    /// What would open the thing they ran into, read from `SubscriptionTier`'s
    /// named lever rather than written as `.plus`: a feature repriced at its
    /// lever would otherwise still be offered, and dismissed, against a tier
    /// nothing had reconsidered.
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
    /// What this tier is called in the interface. One mapping for the whole
    /// feature — separate answers once put "Plus" and "önd Plus" on two
    /// screens describing the same thing.
    var title: String {
        switch self {
        case .free: "Free"
        case .plus: "önd+"
        }
    }
}

extension View {
    /// Presents the paywall, opened on the headline that answers whatever the
    /// person just ran into. A modifier rather than a `.sheet` per site: six
    /// copies of the presentation are six chances to lose the sheet or lead
    /// with the wrong sentence.
    func paywall(for context: PaywallContext, isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(context)
        }
    }
}
