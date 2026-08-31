@testable import OndKit
import Testing

@Suite("Subscription renewal")
@MainActor
struct SubscriptionRenewalTests {
    /// Cancelling changes what happens after the paid period, not the access
    /// already bought. Settings needs both facts so it can keep the önd+ label
    /// while saying when that access ends.
    @Test("A cancelled subscription stays Plus and names its paid-through date")
    func cancelledSubscriptionKeepsAccessUntilExpiry() async {
        let cancelled = transaction(willAutoRenew: false)
        let store = makeStore(entitlements: [cancelled])

        await store.refresh()

        #expect(store.tier == .plus)
        #expect(store.nonRenewingExpirationDate == cancelled.expirationDate)
    }

    /// Unknown renewal information is not a cancellation. StoreKit can refuse
    /// to verify that second signed value while still verifying the transaction
    /// that grants access, and the UI must not turn uncertainty into an end date.
    @Test("Renewing and unknown subscriptions do not claim an ending date")
    func renewingAndUnknownSubscriptionsHaveNoEndingDate() async {
        let front = FakeStoreFront(entitlements: [transaction(willAutoRenew: true)])
        let store = makeStore(front: front)

        await store.refresh()
        #expect(store.nonRenewingExpirationDate == nil)

        front.set([transaction(willAutoRenew: nil)])
        await store.refresh()
        #expect(store.nonRenewingExpirationDate == nil)
    }

    /// A crossgrade can expose the old cancelled transaction beside the new
    /// one. The row may say access ends only when every live answer agrees; if
    /// they do, the furthest paid-through date is the honest one to display.
    @Test("Mixed subscriptions name an end only when every live transaction does")
    func mixedSubscriptionsRequireUnanimousCancellation() async {
        let sooner = transaction(id: 1, expiresIn: 600, willAutoRenew: false)
        let later = transaction(id: 2, expiresIn: 1200, willAutoRenew: false)
        let front = FakeStoreFront(entitlements: [sooner, later])
        let store = makeStore(front: front)

        await store.refresh()
        #expect(store.nonRenewingExpirationDate == later.expirationDate)

        front.set([sooner, transaction(id: 3, willAutoRenew: true)])
        await store.refresh()
        #expect(store.nonRenewingExpirationDate == nil)

        front.set([sooner, transaction(id: 4, willAutoRenew: nil)])
        await store.refresh()
        #expect(store.nonRenewingExpirationDate == nil)
    }

    /// Expiry and revocation are the two ways an active cancellation can stop
    /// being a paid entitlement. Neither may leave its old end date behind.
    @Test("Expiry and revocation clear the tier and ending date")
    func inactiveSubscriptionsClearCancellationMetadata() async {
        let front = FakeStoreFront(entitlements: [transaction(willAutoRenew: false)])
        let store = makeStore(front: front)

        await store.refresh()
        #expect(store.nonRenewingExpirationDate != nil)

        front.set([transaction(expiresIn: -1, willAutoRenew: false)])
        await store.refresh()
        #expect(store.tier == .free)
        #expect(store.nonRenewingExpirationDate == nil)

        front.set([transaction(revoked: true, willAutoRenew: false)])
        await store.refresh()
        #expect(store.tier == .free)
        #expect(store.nonRenewingExpirationDate == nil)
    }

    /// A store over a controlled StoreKit answer and an isolated cache.
    private func makeStore(
        front: FakeStoreFront? = nil,
        entitlements: [SubscriptionTransaction] = []
    ) -> SubscriptionStore {
        SubscriptionStore(
            front: front ?? FakeStoreFront(entitlements: entitlements),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
    }
}
