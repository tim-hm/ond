import Foundation

/// What there is to sell on one cadence, as one answer.
///
/// Three surfaces used to compute this independently — a headline, a button, a
/// price line and a renewal disclosure, each re-deriving "is there a product,
/// and does it carry a trial this person can take" from two optionals. One of
/// them getting it wrong is a button promising days the purchase does not
/// honour, which is a 3.1.2 violation as well as a lie, so it is derived once
/// and read everywhere.
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
/// is a trial to take, and what the year saves.
///
/// Split out on `SessionSyncQueue+Restore.swift`'s terms — the store proper is
/// about entitlement and submission, and these are derived reads over the
/// prices it happens to hold. None of them touches `StoreKit` or the network;
/// they are arithmetic and filtering over `products`.
public extension SubscriptionStore {
    /// The trial on offer anywhere in the group, in days, or `nil` where there
    /// is none this person can take.
    ///
    /// `nil` until the prices load, which is what a screen with nothing from the
    /// App Store yet has to read as "no trial to promise" rather than as one.
    ///
    /// Group-wide, so it answers "is a trial being offered at all". A surface
    /// that names a trial beside a *price* must read the selected product's own
    /// `introductoryOffer` instead — eligibility is per group but the offer is
    /// per product, and App Store Connect can carry one on only the monthly.
    var trialDays: Int? {
        products.compactMap(\.introductoryOffer).first { $0.isEligible }?.trialDays
    }

    /// The price of one cadence, once the App Store has said.
    func product(for plan: SubscriptionPlan) -> SubscriptionProduct? {
        products.first { $0.plan == plan }
    }

    /// The trial on `plan`'s own product, in days, or `nil` where this person
    /// cannot take one on it.
    ///
    /// What every surface naming a trial beside a price has to read, for the
    /// reason [`trialDays`] gives: eligibility is per group, the offer is per
    /// product, and a button promising days the purchase then does not honour
    /// is a 3.1.2 violation as well as a lie.
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

    /// What a button that buys `plan` should say.
    ///
    /// Shared because both surfaces that sell önd+ have one, and a trial
    /// promised in two places has to be promised in the same words. A paid or
    /// unavailable offer names the selected cadence, matching the plan tile the
    /// action belongs to. Onboarding overrides only the unavailable case,
    /// because there the button's other job is to move the flow on.
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

    /// The cadence a surface that offers one plan and no choice should sell.
    ///
    /// Monthly, which is the cheapest way into a trial and the least somebody
    /// is being asked to commit to on a screen they did not go looking for —
    /// unless it is the *yearly* that carries the offer, in which case the
    /// trial is what is being sold and the plan follows it. That fallback is
    /// what keeps a headline read from [`trialDays`] and a button read from
    /// this plan's own offer from ever contradicting each other.
    ///
    /// Onboarding's trial step is the caller. The paywall lets somebody choose,
    /// and defaults to the year, because that is a screen about buying.
    var trialPlan: SubscriptionPlan {
        SubscriptionPlan.allCases.first { trialDays(for: $0) != nil } ?? .monthly
    }

    /// What buying the year saves against paying monthly for one, as a whole
    /// percentage — or `nil` while either price is unknown, or where the year
    /// saves nothing.
    ///
    /// Computed rather than written on the badge, because both prices are the
    /// App Store's: they differ by storefront, they are set independently in
    /// App Store Connect, and a "save 37%" typed into a view is a claim that
    /// goes wrong in every country where the rounding lands differently.
    /// Rounded *down*, so the number on screen is never more than the saving
    /// actually is.
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
