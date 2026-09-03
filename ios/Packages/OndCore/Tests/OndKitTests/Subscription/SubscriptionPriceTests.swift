@testable import OndKit
import Testing

/// What the paywall may draw before the App Store has answered. A file of its
/// own because `SubscriptionTests.swift` is already at the length limit.
@Suite("Waiting for prices")
@MainActor
struct SubscriptionPriceTests {
    /// The paywall holds its prices back while this is true, so nobody buys
    /// against a dash. It must clear on the answer, whatever the answer is:
    /// left true by an answer with nothing, an offline first run would face a
    /// dead button.
    @Test("The wait for prices ends on any answer, including none")
    func theWaitForPricesEnds() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        #expect(store.isAwaitingProducts, "nothing has been asked yet")

        await store.loadProducts()

        #expect(!store.isAwaitingProducts)

        let offline = SubscriptionStore(
            front: FakeStoreFront(sellsNothing: true),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await offline.loadProducts()

        #expect(offline.products.isEmpty)
        #expect(!offline.isAwaitingProducts, "an answer with nothing is still an answer")
    }
}
