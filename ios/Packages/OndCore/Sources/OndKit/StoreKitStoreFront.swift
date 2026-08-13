import Foundation
import StoreKit

/// The only type in the repository that imports `StoreKit`.
///
/// Everything above it works in `SubscriptionTransaction` values, which is what lets the
/// tier rules and the submission ledger be tested on the host with no App Store
/// account, no booted simulator, and no purchase.
///
/// Stateless, and therefore a struct. Holding the resolved `Product`s between
/// the paywall's prices and the same screen's purchase looks worth doing, and is
/// not: it makes this an actor, and an actor's isolated members cannot satisfy a
/// `Sendable` protocol under Swift 6 without a conformance the compiler refuses.
/// `StoreKit` caches product metadata on the device anyway, so the second lookup
/// is a local read rather than the round trip it appears to be.
public struct StoreKitStoreFront: StoreFront {
    public init() {}

    public func products() async -> [SubscriptionProduct] {
        let resolved = await resolve(SubscriptionPlan.allCases.map(\.productIdentifier))

        // Asked once, of the *subscription group* rather than of each product,
        // which is Apple's rule and not an approximation: one trial per Apple ID
        // per group, ever, so taking the monthly trial spends the yearly one
        // too. Both products answer identically, and asking twice would be two
        // sequential awaits in front of a paywall for a single fact.
        let isEligible = await resolved.first?.subscription?.isEligibleForIntroOffer ?? false

        // Built in declaration order — monthly then yearly — rather than in
        // whatever order the App Store answered in, so the paywall's two rows
        // cannot swap between launches.
        return SubscriptionPlan.allCases.compactMap { plan in
            guard let product = resolved.first(where: { $0.id == plan.productIdentifier })
            else { return nil }

            return SubscriptionProduct(
                plan: plan,
                displayPrice: product.displayPrice,
                price: product.price,
                introductoryOffer: introductoryOffer(of: product, isEligible: isEligible)
            )
        }
    }

    /// The free trial on a product, or `nil` where there is none to take.
    ///
    /// A non-free introductory offer answers `nil` — this app sells no such
    /// thing, and reading one as a trial would put "7 days free" over a charge.
    /// Eligibility is passed in rather than read here because it belongs to the
    /// subscription group rather than to this product; see [`products()`].
    private func introductoryOffer(of product: Product, isEligible: Bool) -> IntroductoryOffer? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else {
            return nil
        }

        return IntroductoryOffer(
            trialDays: days(in: offer.period) * offer.periodCount,
            isEligible: isEligible
        )
    }

    /// A subscription period in days.
    ///
    /// The trial this app sells is configured as `P1W`, which arrives as one
    /// *week* rather than seven days — so the copy needs the conversion, and it
    /// is done here rather than in a view. The month and year figures are
    /// nominal, because a trial measured in either is not something the App
    /// Store offers and a calendar would be borrowed accuracy.
    private func days(in period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
    }

    public func currentEntitlements() async -> [SubscriptionTransaction] {
        var entitlements: [SubscriptionTransaction] = []
        for await result in Transaction.currentEntitlements {
            if let transaction = SubscriptionTransaction(result) {
                entitlements.append(transaction)
            }
        }

        return entitlements
    }

    public func updates() -> AsyncStream<SubscriptionTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    // Finished whatever it turned out to say, and before the
                    // yield. An unfinished transaction is redelivered on every
                    // launch for the life of the install, and the entitlement it
                    // grants is durable without it — `currentEntitlements` still
                    // reports it, and the server's own retry is this app's
                    // ledger rather than StoreKit's queue.
                    await result.unsafePayloadValue.finish()

                    if let transaction = SubscriptionTransaction(result) {
                        continuation.yield(transaction)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        guard let product = await resolve([plan.productIdentifier]).first else {
            throw StoreFrontError.productUnavailable
        }

        switch try await product.purchase() {
        case let .success(result):
            await result.unsafePayloadValue.finish()
            guard let transaction = SubscriptionTransaction(result) else {
                throw StoreFrontError.unverified
            }
            return .purchased(transaction)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        // StoreKit's result enum is not frozen, and a case added in a later
        // OS must not stop this compiling. Read as "nothing was bought",
        // which is the only assumption that cannot wrongly entitle anybody.
        @unknown default:
            return .cancelled
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
    }

    /// Asks the App Store for exactly what the caller needs — both cadences for
    /// the paywall's prices, one for the purchase somebody is waiting on.
    private func resolve(_ identifiers: [String]) async -> [Product] {
        await (try? Product.products(for: identifiers)) ?? []
    }
}

private extension SubscriptionTransaction {
    /// `nil` for a transaction `StoreKit` will not vouch for.
    ///
    /// Dropped rather than passed along unverified: the signature is the only
    /// thing separating a real purchase from a tampered one, and this app's
    /// answer to a failed check is the same as the server's — it entitles
    /// nobody.
    init?(_ result: VerificationResult<StoreKit.Transaction>) {
        guard case let .verified(transaction) = result else { return nil }

        self.init(
            id: transaction.id,
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            jws: result.jwsRepresentation,
            isLocallySigned: transaction.environment == .xcode
        )
    }
}
