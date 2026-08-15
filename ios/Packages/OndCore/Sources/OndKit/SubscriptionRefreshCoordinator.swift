import Foundation

/// Orders entitlement reads and bridges the short handoff between a verified
/// transaction and StoreKit's current-entitlements sequence.
@MainActor
final class SubscriptionRefreshCoordinator {
    private var unconfirmedEntitlement: SubscriptionTransaction?
    private var isRefreshing = false
    private var refreshQueued = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Runs one entitlement read at a time. Overlap requests one final reread,
    /// so a snapshot started before a purchase cannot finish after a newer one
    /// and overwrite the paid tier.
    func run(_ operation: @MainActor () async -> Void) async {
        if isRefreshing {
            refreshQueued = true
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }

        isRefreshing = true
        repeat {
            refreshQueued = false
            await operation()
        } while refreshQueued
        isRefreshing = false

        let completedWaiters = waiters
        waiters.removeAll(keepingCapacity: true)
        for waiter in completedWaiters {
            waiter.resume()
        }
    }

    /// Applies access StoreKit has verified and retains it until
    /// `currentEntitlements` catches up. Inactive updates clear the bridge.
    func record(
        _ transaction: SubscriptionTransaction,
        tier: inout SubscriptionTier,
        endingAt: inout Date?
    ) {
        let entitledTier = transaction.entitledTier(at: Date())
        guard entitledTier > .free else {
            if unconfirmedEntitlement?.id == transaction.id {
                unconfirmedEntitlement = nil
            }
            return
        }

        unconfirmedEntitlement = transaction
        tier = max(tier, entitledTier)

        if transaction.willAutoRenew != false {
            endingAt = nil
        }
    }

    /// Adds the verified bridge until StoreKit reports the same transaction.
    /// Expiry and revocation remove it even if that confirmation never arrives.
    func entitlements(
        byAddingUnconfirmedTo reported: [SubscriptionTransaction],
        at moment: Date
    ) -> [SubscriptionTransaction] {
        guard let unconfirmedEntitlement else { return reported }

        guard !reported.contains(where: { $0.id == unconfirmedEntitlement.id }),
              unconfirmedEntitlement.entitledTier(at: moment) > .free
        else {
            self.unconfirmedEntitlement = nil
            return reported
        }

        return reported + [unconfirmedEntitlement]
    }
}
