import Foundation
@testable import OndKit
import Testing

@MainActor
@Suite("Purchase and restore feedback")
struct SubscriptionFeedbackTests {
    @Test("Restore reports whether a verified entitlement exists", arguments: [false, true])
    func restoreOutcome(hasSubscription: Bool) async {
        let store = SubscriptionStore(
            front: FakeStoreFront(entitlements: hasSubscription ? [transaction()] : []),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.restore()

        #expect(store.feedback == (hasSubscription ? .restored : .noSubscription))
        #expect(!store.isBusy)
    }

    @Test("A failed restore does not claim success from an existing subscription")
    func failedRestore() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(
                entitlements: [transaction()],
                restoreError: StoreFrontError.unverified
            ),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.restore()

        #expect(store.tier == .plus)
        #expect(store.feedback == .restoreFailed)
        #expect(!store.isBusy)
    }

    @Test("Cancelling a restore clears earlier feedback and stays quiet")
    func cancelledRestore() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(
                failingWith: StoreFrontError.unverified,
                restoreError: StoreFrontError.cancelled
            ),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await store.purchase(.monthly)
        #expect(store.feedback == .purchaseFailed)

        await store.restore()

        #expect(store.feedback == nil)
        #expect(!store.isBusy)
    }

    @Test("A restore does not erase pending purchase approval")
    func pendingApprovalSurvivesRestore() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(purchaseOutcome: .pending),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await store.purchase(.monthly)
        await store.restore()

        #expect(store.isAwaitingApproval)
        #expect(store.feedback == .noSubscription)
    }

    @Test("Cancelling a purchase is not a failure")
    func cancelledPurchase() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(purchaseOutcome: .cancelled),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await store.purchase(.monthly)

        #expect(store.feedback == nil)
        #expect(store.purchaseState == .idle)
    }
}
