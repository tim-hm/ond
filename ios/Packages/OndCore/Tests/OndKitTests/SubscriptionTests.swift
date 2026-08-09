import Foundation
@testable import OndKit
import Testing

/// A store front that answers from a script, so the tier rules and the
/// submission ledger are exercisable with no App Store account and no booted
/// simulator — which is the whole reason `StoreFront` exists.
private final class FakeStoreFront: StoreFront, @unchecked Sendable {
    private let lock = NSLock()
    private var entitlements: [SubscriptionTransaction]
    private var purchaseError: (any Error)?
    private(set) var purchased: [SubscriptionTier] = []

    init(entitlements: [SubscriptionTransaction] = [], failingWith error: (any Error)? = nil) {
        self.entitlements = entitlements
        purchaseError = error
    }

    func set(_ entitlements: [SubscriptionTransaction]) {
        lock.withLock { self.entitlements = entitlements }
    }

    func products() async -> [SubscriptionProduct] {
        [
            SubscriptionProduct(tier: .plus, displayPrice: "£0.99"),
            SubscriptionProduct(tier: .coach, displayPrice: "£4.99"),
        ]
    }

    func currentEntitlements() async -> [SubscriptionTransaction] {
        lock.withLock { entitlements }
    }

    func updates() -> AsyncStream<SubscriptionTransaction> {
        AsyncStream { $0.finish() }
    }

    func purchase(_ tier: SubscriptionTier) async throws -> PurchaseOutcome {
        let error = lock.withLock {
            purchased.append(tier)
            return purchaseError
        }

        if let error {
            throw error
        }

        return .cancelled
    }

    func restore() async throws {}
}

/// Records every JWS it is handed, and fails on demand.
private final class RecordingEntitlements: EntitlementSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var submitted: [String] = []
    private var shouldFail = false
    private var shouldReject = false
    private var attemptTally = 0

    var received: [String] {
        lock.withLock { submitted }
    }

    /// Every call, refused or not — what the once-per-launch ledger bounds.
    var attempts: Int {
        lock.withLock { attemptTally }
    }

    func fail(_ failing: Bool) {
        lock.withLock { shouldFail = failing }
    }

    func reject(_ rejecting: Bool) {
        lock.withLock { shouldReject = rejecting }
    }

    func submit(_ signedTransaction: String) async throws {
        let (failing, rejecting) = lock.withLock {
            attemptTally += 1
            return (shouldFail, shouldReject)
        }
        if failing {
            throw EntitlementRepositoryError.transport("scripted failure")
        }
        if rejecting {
            throw EntitlementRepositoryError.rejected("`x5c` carries 1 certificates, not 3")
        }
        lock.withLock { submitted.append(signedTransaction) }
    }
}

private func transaction(
    id: UInt64 = 1,
    tier: SubscriptionTier = .plus,
    productID: String? = nil,
    expiresIn: TimeInterval? = 3600,
    revoked: Bool = false,
    jws: String = "jws",
    locallySigned: Bool = false
) -> SubscriptionTransaction {
    SubscriptionTransaction(
        id: id,
        productID: productID ?? tier.productIdentifier ?? "",
        expirationDate: expiresIn.map { Date().addingTimeInterval($0) },
        revocationDate: revoked ? Date() : nil,
        jws: jws,
        isLocallySigned: locallySigned
    )
}

/// A `UserDefaults` nobody else shares, so one test cannot decide another's
/// starting state — the store caches its answer between launches on purpose.
private func scratchDefaults() -> UserDefaults {
    let suite = UserDefaults(suiteName: "plus.tests.\(UUID().uuidString)")
    return suite ?? .standard
}

@Suite("What a transaction entitles")
struct SubscriptionTransactionTests {
    @Test("Each product entitles its own tier")
    func eachProductEntitlesItsTier() {
        let now = Date()

        #expect(transaction(tier: .plus).entitledTier(at: now) == .plus)
        #expect(transaction(tier: .coach).entitledTier(at: now) == .coach)
    }

    /// The expiry is the moment it ends, matching the server's own comparison.
    /// The two sides disagreeing by one instant would show somebody a subscriber
    /// catalogue while the assistant refused them the subscriber allowance.
    @Test("An expired subscription entitles nothing")
    func expiredEntitlesNothing() {
        let expiry = Date()
        let expired = SubscriptionTransaction(
            id: 1,
            productID: SubscriptionTier.coach.productIdentifier ?? "",
            expirationDate: expiry,
            revocationDate: nil,
            jws: "jws"
        )

        #expect(expired.entitledTier(at: expiry) == .free)
        #expect(expired.entitledTier(at: expiry.addingTimeInterval(-1)) == .coach)
    }

    /// A refund ends the entitlement even though the period it paid for has not.
    @Test("A revoked subscription entitles nothing, however far off its expiry")
    func revokedEntitlesNothing() {
        let refunded = transaction(tier: .coach, expiresIn: 86400 * 365, revoked: true)

        #expect(refunded.entitledTier(at: Date()) == .free)
    }

    /// A receipt for a product this build does not sell — the withdrawn yearly
    /// Plus, or something a newer build introduced — must not be read as any
    /// tier at all.
    @Test("A product this build does not sell entitles nothing")
    func unknownProductEntitlesNothing() {
        let stale = transaction(productID: "xyz.holmie.ond.plus.yearly")

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
        let front = FakeStoreFront(entitlements: [transaction(tier: .coach)])
        let server = RecordingEntitlements()
        server.fail(true)
        let store = SubscriptionStore(
            front: front,
            entitlements: server,
            defaults: scratchDefaults()
        )

        await store.refresh()

        #expect(store.tier == .coach)
        #expect(server.received.isEmpty)
    }

    /// A Plus subscriber gets the catalogue and not the assistant. This is the
    /// one place the two gates could be confused for each other, and confusing
    /// them either locks a payer out or gives the model away.
    @Test("Plus opens the catalogue and not the assistant")
    func plusIsNotCoach() async {
        let front = FakeStoreFront(entitlements: [transaction(tier: .plus)])
        let store = SubscriptionStore(
            front: front,
            entitlements: RecordingEntitlements(),
            defaults: scratchDefaults()
        )

        await store.refresh()

        #expect(store.tier >= .plus, "Plus opens the catalogue")
        #expect(store.tier < .coach, "and not the assistant")
    }

    /// A crossgrade can leave both subscriptions momentarily visible, and the
    /// answer during that moment should be the one the person is paying for.
    @Test("Holding two entitlements resolves to the higher one")
    func theHigherEntitlementWins() async {
        let front = FakeStoreFront(entitlements: [
            transaction(id: 1, tier: .plus),
            transaction(id: 2, tier: .coach),
        ])
        let store = SubscriptionStore(
            front: front,
            entitlements: RecordingEntitlements(),
            defaults: scratchDefaults()
        )

        await store.refresh()

        #expect(store.tier == .coach)
    }

    /// Every launch and every foreground calls `refresh`. Sending the same
    /// purchase each time would be a request per foreground for the life of the
    /// subscription.
    @Test("A transaction is submitted once, however often the store refreshes")
    func submissionHappensOnce() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-plus")])
        let server = RecordingEntitlements()
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
        let server = RecordingEntitlements()
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
        let server = RecordingEntitlements()
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

    /// The coach's retry is a resubmission, not a re-read: the tier will not
    /// change until a submission succeeds, so retrying must clear the ledger
    /// and offer the transaction again — and an acceptance clears the refusal.
    @Test("Resubmit re-offers a refused transaction, and acceptance clears the refusal")
    func resubmitReoffers() async {
        let front = FakeStoreFront(entitlements: [transaction(jws: "jws-real")])
        let server = RecordingEntitlements()
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
        let front = FakeStoreFront(entitlements: [transaction(tier: .coach)])
        let defaults = scratchDefaults()
        let store = SubscriptionStore(
            front: front,
            entitlements: RecordingEntitlements(),
            defaults: defaults
        )

        await store.refresh()
        #expect(store.tier == .coach)
        #expect(relaunch(over: defaults, front: front).tier == .coach)

        front.set([])
        await store.refresh()
        #expect(store.tier == .free)
        #expect(relaunch(over: defaults, front: front).tier == .free)
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
            entitlements: RecordingEntitlements(),
            defaults: scratchDefaults()
        )

        await store.purchase(.plus)

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
            entitlements: RecordingEntitlements(),
            defaults: scratchDefaults()
        )

        await store.purchase(.plus)

        #expect(!store.isUnavailable)
        #expect(store.purchaseState == .idle)
    }

    /// A fresh store over the same defaults, which is what a cold launch is.
    private func relaunch(over defaults: UserDefaults, front: FakeStoreFront) -> SubscriptionStore {
        SubscriptionStore(front: front, entitlements: RecordingEntitlements(), defaults: defaults)
    }
}
