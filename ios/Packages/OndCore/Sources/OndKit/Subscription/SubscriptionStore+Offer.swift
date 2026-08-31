import Foundation

/// What there is to sell on one cadence, as one answer. Derived once and read
/// everywhere: surfaces that each re-derive "is there a product, and a trial
/// this person can take" from two optionals can disagree, and a button that
/// promises days the purchase does not honour violates App Review 3.1.2.
public enum SubscriptionOffer: Sendable, Equatable {
    /// The App Store answered with nothing under this build's product ids: no
    /// signal, a simulator run with no `StoreKit` configuration, or a product
    /// not yet approved. Nothing can be bought, and a surface saying so is the
    /// honest degradation.
    case unavailable

    /// A price, and no trial this Apple ID may still take.
    case paid(price: String)

    /// A trial, and the price that follows it. Both, always, because App
    /// Review's 3.1.2 disclosure needs them in one sentence.
    case trial(days: Int, price: String)
}

/// What a paywall reads off the store: which cadence costs what, whether there
/// is a trial to take, and what the year saves. These are derived reads over
/// `products`; none touches `StoreKit` or the network.
public extension SubscriptionStore {
    /// The trial on offer anywhere in the group, in days, or `nil` where there
    /// is none this person can take — including before the prices load, which
    /// a screen must read as "no trial to promise". A surface naming a trial
    /// beside a price must read that product's own `introductoryOffer` instead:
    /// eligibility is per group, but the offer is per product.
    var trialDays: Int? {
        products.compactMap(\.introductoryOffer).first { $0.isEligible }?.trialDays
    }

    /// The price of one cadence, once the App Store has said.
    func product(for plan: SubscriptionPlan) -> SubscriptionProduct? {
        products.first { $0.plan == plan }
    }

    /// The trial on `plan`'s own product, in days, or `nil` where this person
    /// cannot take one on it. Every surface naming a trial beside a price must
    /// read this rather than the group-wide [`trialDays`]: the offer is per
    /// product, and promised days the purchase does not honour violate 3.1.2.
    func trialDays(for plan: SubscriptionPlan) -> Int? {
        product(for: plan)?.introductoryOffer.flatMap { $0.isEligible ? $0.trialDays : nil }
    }

    /// What there is to sell on `plan`, as the one value every surface reads.
    func offer(for plan: SubscriptionPlan) -> SubscriptionOffer {
        guard let product = product(for: plan) else { return .unavailable }
        guard let days = trialDays(for: plan) else {
            return .paid(price: product.displayPrice)
        }

        return .trial(days: days, price: product.displayPrice)
    }

    /// What a button that buys `plan` should say. Shared so both surfaces that
    /// sell önd+ promise a trial in the same words. A paid or unavailable offer
    /// names the selected cadence. Onboarding overrides only the unavailable
    /// case, because there the button must also move the flow on.
    func purchaseTitle(for plan: SubscriptionPlan) -> String {
        switch offer(for: plan) {
        case let .trial(days, _): "Try \(days) days free"
        case .paid, .unavailable:
            switch plan {
            case .monthly: "Subscribe monthly"
            case .yearly: "Subscribe yearly"
            }
        }
    }

    /// The cadence a one-plan surface (onboarding's trial step) should sell:
    /// monthly, the cheapest way into a trial and the smallest commitment —
    /// unless the yearly carries the offer, in which case the plan follows the
    /// trial. That fallback keeps a headline read from [`trialDays`] and a
    /// button read from this plan's own offer from contradicting each other.
    var trialPlan: SubscriptionPlan {
        SubscriptionPlan.allCases.first { trialDays(for: $0) != nil } ?? .monthly
    }

    /// What buying the year saves against paying monthly, as a whole
    /// percentage; `nil` while either price is unknown or the year saves
    /// nothing. Computed rather than typed into a view because both prices are
    /// the App Store's and differ by storefront. Rounded down, so the number on
    /// screen is never more than the actual saving.
    var annualSaving: Int? {
        guard let monthly = product(for: .monthly)?.price,
              let yearly = product(for: .yearly)?.price,
              monthly > 0
        else {
            return nil
        }

        let saved = ((monthly * 12 - yearly) / (monthly * 12)) * 100

        let percent = Int(NSDecimalNumber(decimal: saved).doubleValue)
        return percent > 0 ? percent : nil
    }
}
