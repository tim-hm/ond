import Foundation

/// What a paywall reads off the store: which cadence costs what, whether there
/// is a trial to take, and what the year saves.
///
/// Split out on `SessionSyncQueue+Restore.swift`'s terms — the store proper is
/// about entitlement and submission, and these are derived reads over the
/// prices it happens to hold. None of them touches `StoreKit` or the network;
/// they are arithmetic and filtering over `products`.
public extension SubscriptionStore {
    /// Whether this Apple ID may still take the free trial, which every piece
    /// of trial copy branches on.
    ///
    /// False until the prices load, and false rather than nil: a screen that
    /// has not heard from the App Store yet must say "Subscribe" rather than
    /// promise a trial it may turn out this person has already had.
    var isEligibleForTrial: Bool {
        products.contains { $0.introductoryOffer?.isEligible == true }
    }

    /// The trial on offer, in days, or `nil` where there is none this person
    /// can take.
    var trialDays: Int? {
        products.compactMap(\.introductoryOffer).first { $0.isEligible }?.trialDays
    }

    /// The price of one cadence, once the App Store has said.
    func product(for plan: SubscriptionPlan) -> SubscriptionProduct? {
        products.first { $0.plan == plan }
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
