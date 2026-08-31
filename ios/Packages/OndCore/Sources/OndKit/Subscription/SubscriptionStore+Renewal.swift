import Foundation

extension SubscriptionStore {
    /// The last paid-through date only when every live transaction explicitly
    /// says it will not renew. During a crossgrade, one renewing or unverifiable
    /// answer wins so the UI never overstates that access is ending.
    static func nonRenewingExpirationDate(
        in entitlements: [SubscriptionTransaction]
    ) -> Date? {
        guard entitlements.allSatisfy({ $0.willAutoRenew == false }) else {
            return nil
        }

        return entitlements.map(\.expirationDate).max()
    }
}
