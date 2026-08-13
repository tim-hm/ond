import Foundation
@testable import OndKit
import Testing

/// A store front that answers from a script, so the tier rules and the
/// submission ledger are exercisable with no App Store account and no booted
/// simulator — which is the whole reason `StoreFront` exists.
///
/// A file of its own for `SessionSyncDoubles`' reason: the doubles put
/// `SubscriptionTests.swift` over `file_length`, and they are the half a
/// reader can skip.
final class FakeStoreFront: StoreFront, @unchecked Sendable {
    private let lock = NSLock()
    private var entitlements: [SubscriptionTransaction]
    private var purchaseError: (any Error)?
    private(set) var purchased: [SubscriptionPlan] = []

    /// Whether the scripted products carry a trial this person may take. A
    /// parameter because every piece of trial copy branches on it, and the
    /// ineligible half — somebody who subscribed once already — is the one a
    /// test would otherwise never reach.
    private let isEligibleForTrial: Bool

    init(
        entitlements: [SubscriptionTransaction] = [],
        failingWith error: (any Error)? = nil,
        isEligibleForTrial: Bool = true
    ) {
        self.entitlements = entitlements
        purchaseError = error
        self.isEligibleForTrial = isEligibleForTrial
    }

    func set(_ entitlements: [SubscriptionTransaction]) {
        lock.withLock { self.entitlements = entitlements }
    }

    /// The two cadences at prices whose ratio is the shipping one — a year for
    /// the price of about seven and a half months — so a test asserting the
    /// saving is asserting arithmetic rather than a coincidence.
    func products() async -> [SubscriptionProduct] {
        [
            SubscriptionProduct(
                plan: .monthly,
                displayPrice: "£1.99",
                price: 1.99,
                introductoryOffer: IntroductoryOffer(
                    trialDays: 7,
                    isEligible: isEligibleForTrial
                )
            ),
            SubscriptionProduct(
                plan: .yearly,
                displayPrice: "£14.99",
                price: 14.99,
                introductoryOffer: IntroductoryOffer(
                    trialDays: 7,
                    isEligible: isEligibleForTrial
                )
            ),
        ]
    }

    func currentEntitlements() async -> [SubscriptionTransaction] {
        lock.withLock { entitlements }
    }

    func updates() -> AsyncStream<SubscriptionTransaction> {
        AsyncStream { $0.finish() }
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        let error = lock.withLock {
            purchased.append(plan)
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
final class ScriptedEntitlements: EntitlementSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var submitted: [String] = []
    private var shouldFail = false
    private var shouldReject = false
    private var shouldHold = false
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

    func hold(_ holding: Bool) {
        lock.withLock { shouldHold = holding }
    }

    func submit(_ signedTransaction: String) async throws {
        let (failing, rejecting, holding) = lock.withLock {
            attemptTally += 1
            return (shouldFail, shouldReject, shouldHold)
        }
        if failing {
            throw EntitlementRepositoryError.transport("scripted failure")
        }
        if rejecting {
            throw EntitlementRepositoryError.rejected("`x5c` carries 1 certificates, not 3")
        }
        if holding {
            throw EntitlementRepositoryError.held(
                "the signed transaction is claimed by another installation"
            )
        }
        lock.withLock { submitted.append(signedTransaction) }
    }
}

func transaction(
    id: UInt64 = 1,
    plan: SubscriptionPlan = .monthly,
    productID: String? = nil,
    expiresIn: TimeInterval? = 3600,
    revoked: Bool = false,
    jws: String = "jws",
    locallySigned: Bool = false
) -> SubscriptionTransaction {
    SubscriptionTransaction(
        id: id,
        productID: productID ?? plan.productIdentifier,
        expirationDate: expiresIn.map { Date().addingTimeInterval($0) },
        revocationDate: revoked ? Date() : nil,
        jws: jws,
        isLocallySigned: locallySigned
    )
}

/// A `UserDefaults` nobody else shares, so one test cannot decide another's
/// starting state — the store caches its answer between launches on purpose.
func scratchDefaults() -> UserDefaults {
    let suite = UserDefaults(suiteName: "plus.tests.\(UUID().uuidString)")
    return suite ?? .standard
}
