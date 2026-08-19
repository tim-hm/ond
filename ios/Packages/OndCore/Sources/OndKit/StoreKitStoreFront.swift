import Foundation
import os
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
    private static let logger = Logger(category: "subscription")

    typealias ProductLookup = @Sendable ([String]) async throws -> [Product]

    /// The units StoreKit currently defines, plus the future case production's
    /// `@unknown default` maps onto.
    ///
    /// Kept inside this boundary rather than added to `IntroductoryOffer`: the
    /// app renders days, and an unknown StoreKit unit is an absent offer rather
    /// than a new unit the rest of the app should learn to display.
    enum PeriodUnit: Sendable {
        case day
        case week
        case month
        case year
        case unsupported
    }

    /// The verified transaction fields this boundary promotes into OndKit.
    struct TransactionFields: Sendable {
        let id: UInt64
        let productID: String
        let expirationDate: Date?
        let revocationDate: Date?
        let willAutoRenew: Bool?
        let jws: String
        let isLocallySigned: Bool
    }

    private let productLookup: ProductLookup

    public init() {
        productLookup = { identifiers in
            try await Product.products(for: identifiers)
        }
    }

    /// Creates the production boundary over a controlled lookup.
    ///
    /// Internal so host tests can prove that a failed lookup and an empty
    /// successful lookup stay different without making StoreKit's `Product`
    /// constructible or weakening `StoreFront.products()` into a throwing API.
    ///
    /// - Parameter productLookup: the operation that resolves App Store product
    ///   identifiers.
    init(productLookup: @escaping ProductLookup) {
        self.productLookup = productLookup
    }

    public func products() async -> [SubscriptionProduct] {
        let resolved: [Product]
        do {
            resolved = try await resolve(SubscriptionPlan.allCases.map(\.productIdentifier))
        } catch {
            Self.logger.notice(
                "the App Store did not answer for the products: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }

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
                monthlyEquivalentPrice: plan == .yearly
                    ? (product.price / 12).formatted(product.priceFormatStyle)
                    : nil,
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

        return Self.introductoryOffer(
            periodValue: offer.period.value,
            periodCount: offer.periodCount,
            unit: PeriodUnit(offer.period.unit),
            isEligible: isEligible
        )
    }

    /// A free-trial period as the offer the app can safely render.
    ///
    /// The trial this app sells is configured as `P1W`, which arrives as one
    /// *week* rather than seven days — so the copy needs the conversion, and it
    /// is done here rather than in a view. The month and year figures are
    /// nominal, because a trial measured in either is not something the App
    /// Store offers and a calendar would be borrowed accuracy. An unsupported
    /// future unit produces no offer: using its bare value as days would put a
    /// promise on the paywall that the App Store never made.
    static func introductoryOffer(
        periodValue: Int,
        periodCount: Int,
        unit: PeriodUnit,
        isEligible: Bool
    ) -> IntroductoryOffer? {
        let daysPerPeriod: Int
        switch unit {
        case .day: daysPerPeriod = 1
        case .week: daysPerPeriod = 7
        case .month: daysPerPeriod = 30
        case .year: daysPerPeriod = 365
        case .unsupported: return nil
        }

        let (onePeriod, periodOverflowed) = periodValue.multipliedReportingOverflow(
            by: daysPerPeriod
        )
        let (trialDays, countOverflowed) = onePeriod.multipliedReportingOverflow(by: periodCount)
        guard !periodOverflowed, !countOverflowed, trialDays > 0 else { return nil }

        return IntroductoryOffer(trialDays: trialDays, isEligible: isEligible)
    }

    public func currentEntitlements() async -> [SubscriptionTransaction] {
        var entitlements: [SubscriptionTransaction] = []
        for await result in Transaction.currentEntitlements {
            if let transaction = await subscriptionTransaction(result) {
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

                    if let transaction = await subscriptionTransaction(result) {
                        continuation.yield(transaction)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        let resolved = try await resolve([plan.productIdentifier])
        guard let product = resolved.first(where: { $0.id == plan.productIdentifier }) else {
            throw StoreFrontError.productUnavailable
        }

        switch try await product.purchase() {
        case let .success(result):
            await result.unsafePayloadValue.finish()
            guard let transaction = await subscriptionTransaction(result) else {
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
    private func resolve(_ identifiers: [String]) async throws -> [Product] {
        try await productLookup(identifiers)
    }

    /// `nil` for a transaction `StoreKit` will not vouch for.
    ///
    /// Dropped rather than passed along unverified: the signature is the only
    /// thing separating a real purchase from a tampered one, and this app's
    /// answer to a failed check is the same as the server's — it entitles
    /// nobody.
    private func subscriptionTransaction(
        _ result: VerificationResult<StoreKit.Transaction>
    ) async -> SubscriptionTransaction? {
        guard case let .verified(transaction) = result else { return nil }
        let willAutoRenew = await renewalIntent(for: transaction)

        return Self.subscriptionTransaction(TransactionFields(
            id: transaction.id,
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            willAutoRenew: willAutoRenew,
            jws: result.jwsRepresentation,
            isLocallySigned: transaction.environment == .xcode
        ))
    }

    /// Promotes only expiring StoreKit values into the subscription domain.
    ///
    /// Internal so host tests can pin the fail-closed rule without fabricating
    /// Apple's unconstructible transaction type.
    static func subscriptionTransaction(_ fields: TransactionFields) -> SubscriptionTransaction? {
        guard let expirationDate = fields.expirationDate else { return nil }

        return SubscriptionTransaction(
            id: fields.id,
            productID: fields.productID,
            expirationDate: expirationDate,
            revocationDate: fields.revocationDate,
            willAutoRenew: fields.willAutoRenew,
            jws: fields.jws,
            isLocallySigned: fields.isLocallySigned
        )
    }

    /// Auto-renewal only when both signed StoreKit values are verified.
    private func renewalIntent(for transaction: StoreKit.Transaction) async -> Bool? {
        guard let status = await transaction.subscriptionStatus,
              case let .verified(renewal) = status.renewalInfo
        else {
            return nil
        }

        return renewal.willAutoRenew
    }
}

private extension StoreKitStoreFront.PeriodUnit {
    /// Reduces StoreKit's open-ended unit enum to the units this build can
    /// convert without guessing.
    init(_ unit: Product.SubscriptionPeriod.Unit) {
        switch unit {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .year: self = .year
        @unknown default: self = .unsupported
        }
    }
}
