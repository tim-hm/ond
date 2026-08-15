import Foundation
@testable import OndKit
import Testing

@Suite("What a transaction entitles")
struct SubscriptionTransactionTests {
    /// Both cadences buy the same thing, which is what makes the yearly plan a
    /// price rather than a product. A build that read one of them as free would
    /// lock out whoever chose it.
    @Test("Both cadences entitle önd+")
    func bothCadencesEntitlePlus() {
        let now = Date()

        #expect(transaction(plan: .monthly).entitledTier(at: now) == .plus)
        #expect(transaction(plan: .yearly).entitledTier(at: now) == .plus)
    }

    /// The expiry is the moment it ends, matching the server's own comparison.
    /// The two sides disagreeing by one instant would show somebody a subscriber
    /// catalogue while the assistant refused them the subscriber allowance.
    @Test("An expired subscription entitles nothing")
    func expiredEntitlesNothing() {
        let expiry = Date()
        let expired = SubscriptionTransaction(
            id: 1,
            productID: SubscriptionPlan.monthly.productIdentifier,
            expirationDate: expiry,
            revocationDate: nil,
            jws: "jws"
        )

        #expect(expired.entitledTier(at: expiry) == .free)
        #expect(expired.entitledTier(at: expiry.addingTimeInterval(-1)) == .plus)
    }

    /// A refund ends the entitlement even though the period it paid for has not.
    @Test("A revoked subscription entitles nothing, however far off its expiry")
    func revokedEntitlesNothing() {
        let refunded = transaction(plan: .yearly, expiresIn: 86400 * 365, revoked: true)

        #expect(refunded.entitledTier(at: Date()) == .free)
    }

    /// A receipt for a product this build does not sell — a retired Coach tier the
    /// single-tier collapse withdrew, or something a newer build introduced —
    /// must not be read as any tier at all.
    @Test("A product this build does not sell entitles nothing")
    func unknownProductEntitlesNothing() {
        let stale = transaction(productID: "xyz.holmie.ond.coach.monthly")

        #expect(stale.entitledTier(at: Date()) == .free)
    }

    /// The refund case the ledger exists for: the same transaction arrives twice
    /// with different meanings, and a key that ignored the revocation would file
    /// the second one as already sent.
    @Test("A revocation is a different submission from the purchase it revokes")
    func revocationHasItsOwnLedgerKey() {
        #expect(transaction(id: 7).submissionKey != transaction(id: 7, revoked: true).submissionKey)
        #expect(transaction(id: 7).submissionKey == transaction(id: 7, jws: "other").submissionKey)
    }
}

@Suite("Plus store")
@MainActor
struct SubscriptionStoreTests {
    /// The store reads the entitlement from the device and reports it without
    /// the server having said anything — the offline-first promise, stated as a
    /// test.
    @Test("A subscription on the device is live before any server call succeeds")
    func deviceEntitlementIsEnough() async {
        let front = FakeStoreFront(entitlements: [transaction(plan: .monthly)])
        let server = ScriptedEntitlements()
        server.fail(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()

        #expect(store.tier == .plus)
        #expect(server.received.isEmpty)
    }

    /// A crossgrade can leave both cadences momentarily visible, and a lapsed
    /// one must not pull a live one down: the answer is the best of what
    /// `StoreKit` reports rather than the first of it.
    @Test("A lapsed transaction beside a live one resolves to the live one")
    func theLiveEntitlementWins() async {
        let front = FakeStoreFront(entitlements: [
            transaction(id: 1, plan: .monthly, expiresIn: -60),
            transaction(id: 2, plan: .yearly),
        ])
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.refresh()

        #expect(store.tier == .plus)
    }

    /// The trial branches every piece of copy on the paywall, and eligibility is
    /// one trial per Apple ID per subscription group ever — so somebody who
    /// subscribed once already must be offered the price rather than a promise
    /// the App Store would not keep.
    @Test("The trial is offered only to somebody who can still take it")
    func theTrialFollowsEligibility() async {
        let eligible = SubscriptionStore(
            front: FakeStoreFront(),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await eligible.loadProducts()
        #expect(eligible.trialDays == 7)

        let spent = SubscriptionStore(
            front: FakeStoreFront(isEligibleForTrial: false),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await spent.loadProducts()
        #expect(spent.trialDays == nil, "no trial to name means no trial copy")
    }

    /// The badge on the yearly row is arithmetic over two App Store prices, so
    /// it is right in every storefront rather than in the one it was typed for.
    /// Rounded down, so the number on screen is never more than the saving is.
    @Test("The annual saving is computed from the two prices")
    func theAnnualSavingIsComputed() async {
        let store = SubscriptionStore(
            front: FakeStoreFront(),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        #expect(store.annualSaving == nil, "no prices, no claim")

        await store.loadProducts()

        // 14.99 against 12 x 1.99 = 23.88, which is 37.2% off.
        #expect(store.annualSaving == 37)
    }

    /// Every launch and every foreground calls `refresh`. Sending the same
    /// purchase each time would be a request per foreground for the life of the
    /// subscription.
    @Test("A transaction is submitted once, however often the store refreshes")
    func submissionHappensOnce() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-plus")])
        let server = ScriptedEntitlements()
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(server.received == ["jws-plus"])
    }

    /// A failed submission must not be recorded as done. This is the whole of
    /// the retry policy: the next attempt tries again because nothing was
    /// written.
    @Test("A failed submission is retried on the next refresh")
    func failedSubmissionIsRetried() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-plus")])
        let server = ScriptedEntitlements()
        server.fail(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()
        #expect(server.received.isEmpty)

        server.fail(false)
        await store.refresh()
        #expect(server.received == ["jws-plus"])
    }

    /// The reason used to arrive on the wire and be dropped, which cost an
    /// afternoon. A refusal is recorded with whether it was the dev build
    /// working as designed — the locally signed transaction the server can
    /// never verify — and is not retried within the launch: the same bytes
    /// would be refused the same way.
    @Test("A refusal is recorded, named, and not retried within the launch")
    func refusalIsRecordedAndNotRetried() async {
        let front = FakeStoreFront(entitlements: [transaction(
            jws: "jws-local",
            locallySigned: true
        )])
        let server = ScriptedEntitlements()
        server.reject(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()
        #expect(store.lastSubmission == .refusedLocallySigned)

        await store.refresh()
        #expect(server.attempts == 1, "a refused submission is not re-sent this launch")
    }

    /// The transfer cooldown is a hold, not a refusal: a reinstall inside the
    /// 24-hour window is told to wait, keeps offering the transaction, and
    /// completes the transfer by itself once the hold lifts — which is why
    /// the submission key must not settle the way a refusal's does.
    @Test("A held transaction says wait, keeps trying, and settles when the hold lifts")
    func heldTransactionCompletesWhenTheCooldownPasses() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-plus")])
        let server = ScriptedEntitlements()
        server.hold(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()
        #expect(store.lastSubmission == .held)
        #expect(server.received.isEmpty)

        server.hold(false)
        await store.refresh()
        #expect(server.received == ["jws-plus"], "the next refresh completes the transfer")
        #expect(store.lastSubmission == nil, "an accepted submission clears the hold notice")
    }

    /// The coach's retry is a resubmission, not a re-read: the tier will not
    /// change until a submission succeeds, so retrying must clear the ledger
    /// and offer the transaction again — and an acceptance clears the refusal.
    @Test("Resubmit re-offers a refused transaction, and acceptance clears the refusal")
    func resubmitReoffers() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-real")])
        let server = ScriptedEntitlements()
        server.reject(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()
        #expect(
            store.lastSubmission == .refused,
            "an Apple-signed refusal is the alarming kind"
        )

        server.reject(false)
        await store.resubmit()
        #expect(store.lastSubmission == nil)
        #expect(server.received == ["jws-real"])
    }

    /// The cache is what stops the catalogue re-locking itself on every cold
    /// launch, so it has to survive one — and it has to survive one in both
    /// directions. A cache that only ever went up would leave an ex-subscriber
    /// on Coach forever.
    @Test("The tier survives a launch, and so does losing it")
    func theTierSurvivesALaunch() async {
        let front = FakeStoreFront(entitlements: [transaction(plan: .yearly)])
        let defaults = scratchDefaults()
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: defaults
        )

        await store.refresh()
        #expect(store.tier == .plus)
        #expect(relaunch(over: defaults, front: front).tier == .plus)

        front.set([])
        await store.refresh()
        #expect(store.tier == .free)
        #expect(relaunch(over: defaults, front: front).tier == .free)
    }

    /// A successful purchase carries a verified transaction of its own. StoreKit's
    /// entitlement sequence can lag that result by a turn, and treating the empty
    /// snapshot as authoritative would send the person back to Settings as Free.
    @Test("A verified purchase stays live until current entitlements catches up")
    func purchaseBridgesTheEntitlementHandoff() async {
        let purchased = transaction(jws: "jws-purchased")
        let front = FakeStoreFront(purchaseOutcome: .purchased(purchased))
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.purchase(.monthly)
        #expect(store.tier == .plus)

        await store.refresh()
        #expect(store.tier == .plus, "an early empty snapshot cannot undo the purchase")

        front.set([purchased])
        await store.refresh()
        front.set([])
        await store.refresh()
        #expect(store.tier == .free, "StoreKit becomes authoritative after confirmation")
    }

    /// Foregrounding and the transaction listener can request refreshes together.
    /// If both reads run concurrently, a stale pre-purchase snapshot can complete
    /// last and replace önd+ with Free.
    @Test("Overlapping refreshes finish on the newest entitlement snapshot")
    func overlappingRefreshesAreSerialized() async {
        let front = DelayedStoreFront(first: [], then: [transaction()])
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        let staleRefresh = Task { await store.refresh() }
        await front.waitForFirstRequest()
        let currentRefresh = Task { await store.refresh() }

        await currentRefresh.value
        await staleRefresh.value

        #expect(await front.requests == 2)
        #expect(store.tier == .plus)
    }

    /// Entitlement reads are asynchronous, so the instant used for expiry must
    /// be after StoreKit answers. Capturing it before the await can grant access
    /// for a period that ended while the read was in flight.
    @Test("Refresh evaluates expiry after StoreKit answers")
    func refreshUsesTheAnswerTimeForExpiry() async {
        let expiring = transaction(expiresIn: 0.05)
        let front = DelayedStoreFront(first: [expiring], then: [])
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.refresh()
        #expect(store.tier == .free)
    }

    /// The regression this suite exists for. A build the App Store has no
    /// products for cannot sell anything, and the failure has to be legible: it
    /// once looked exactly like a cancelled purchase, so a paywall whose buttons
    /// did nothing read as a broken subscription rather than as a run launched
    /// without its `StoreKit` configuration.
    @Test("A build with nothing on sale says so rather than looking cancelled")
    func nothingOnSaleIsItsOwnState() async {
        let front = FakeStoreFront(failingWith: StoreFrontError.productUnavailable)
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.purchase(.monthly)

        #expect(store.isUnavailable)
        #expect(!store.isBusy, "the button comes back, because retrying is free")
        #expect(store.tier == .free, "and nothing was granted")
    }

    /// The other half of the same rule: an ordinary failure stays silent, so the
    /// notice above means what it says rather than appearing on every dropped
    /// connection.
    @Test("An ordinary purchase failure leaves the paywall as it was")
    func anOrdinaryFailureIsSilent() async {
        let front = FakeStoreFront(failingWith: StoreFrontError.unverified)
        let store = SubscriptionStore(
            front: front,
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )

        await store.purchase(.monthly)

        #expect(!store.isUnavailable)
        #expect(store.purchaseState == .idle)
    }

    /// A fresh store over the same defaults, which is what a cold launch is.
    private func relaunch(over defaults: UserDefaults, front: FakeStoreFront) -> SubscriptionStore {
        SubscriptionStore(front: front, entitlements: ScriptedEntitlements(), defaults: defaults)
    }
}
