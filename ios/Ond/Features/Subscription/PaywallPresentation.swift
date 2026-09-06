import OndKit
import SwiftUI

enum PaywallContext: Sendable, Equatable {
    /// A leaderboard, on the phone or behind its door.
    case leaderboards
    case health
    /// Anything that needs the wrist and the phone working together.
    case watch
    /// Settings, and anywhere else nobody ran into a wall to get here.
    case general

    var headline: String {
        switch self {
        case .watch: "Start on your phone. Follow on your wrist."
        case .health: "Put your practice in context."
        case .leaderboards: "Share your practice, on your terms."
        case .general: "Make room for a regular breathing practice."
        }
    }

    var detail: String {
        switch self {
        case .watch: "Choose the session on your phone and follow its guidance on your Apple Watch."
        case .health: "See recent heart and sleep trends alongside your practice."
        case .leaderboards: "Choose whether to appear on the boards. Your name and participation are optional."
        case .general: "Connect your phone and Apple Watch, see recent Health trends, and support the care behind every practice."
        }
    }

    /// What would open the thing they ran into, read from `SubscriptionTier`'s
    /// named lever rather than written as `.plus`: a feature repriced at its
    /// lever would otherwise still be offered, and dismissed, against a tier
    /// nothing had reconsidered.
    var requires: SubscriptionTier {
        switch self {
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

    /// What a switch says under its label while önd+ is what it needs. One
    /// mapping for the same reason `title` is one: onboarding asks these
    /// questions first and Settings asks them again, and two spellings of the
    /// same fact read as two different facts.
    static let plusRequirementNote = "Needs \(plus.title)"
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
