import Foundation

/// The free trial attached to a subscription, and whether this person can
/// still take it. Only free trials are modelled: the app sells no pay-up-front
/// or pay-as-you-go introductory offers, so a type that could express them
/// would be a paywall branch nothing takes.
public struct IntroductoryOffer: Sendable, Equatable {
    /// How long the trial runs, in days. Rendered rather than computed from:
    /// "Try 7 days free" is the sentence, and App Review's 3.1.2 disclosure
    /// needs the same number beside the price that follows it.
    public let trialDays: Int

    /// Whether this Apple ID may still take the trial. Apple grants one trial
    /// per Apple ID per subscription group, ever, so a lapsed subscriber is
    /// offered the price, not the trial. `StoreKit` answers this from the
    /// account, not from anything this app stores.
    public let isEligible: Bool

    /// - Parameters:
    ///   - trialDays: how long the trial runs, already converted from whatever
    ///     unit the App Store expressed it in.
    ///   - isEligible: whether this Apple ID may still take it.
    public init(trialDays: Int, isEligible: Bool) {
        self.trialDays = trialDays
        self.isEligible = isEligible
    }
}

/// One of the subscriptions this app sells, in the app's vocabulary. Carries
/// only what a paywall draws: each of `Product`'s many extra fields would be a
/// reason for a view to reach past this boundary.
public struct SubscriptionProduct: Sendable, Equatable {
    /// Which cadence this is billed at. The identity of the product, because
    /// both of them grant the same tier.
    public let plan: SubscriptionPlan

    /// Already formatted for the storefront the person is buying from. Never
    /// composed here: the App Store owns the currency, the symbol's position,
    /// and whether the amount rounds — and it varies by country.
    public let displayPrice: String

    /// The amount as a number, only ever divided by another `price` to compute
    /// the yearly saving. Never rendered: composing a price from this would put
    /// the currency symbol in the wrong place in half the world, which
    /// `displayPrice` exists to prevent.
    public let price: Decimal

    /// The yearly price as a storefront-formatted monthly equivalent; nil for
    /// monthly products and for boundaries that cannot format a derived amount
    /// safely. Not derived in a view: only StoreKit knows the locale rules that
    /// turn a decimal into a price.
    public let monthlyEquivalentPrice: String?

    /// The trial on offer, or `nil` where this build's product carries none.
    /// Absent and ineligible are deliberately different: one is a product
    /// without a trial, the other a person who has already had theirs.
    public let introductoryOffer: IntroductoryOffer?

    /// Which tier buying this grants. Never `.free`.
    public var tier: SubscriptionTier {
        plan.tier
    }

    public init(
        plan: SubscriptionPlan,
        displayPrice: String,
        price: Decimal,
        monthlyEquivalentPrice: String? = nil,
        introductoryOffer: IntroductoryOffer? = nil
    ) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.price = price
        self.monthlyEquivalentPrice = monthlyEquivalentPrice
        self.introductoryOffer = introductoryOffer
    }
}

/// One `StoreKit` transaction, reduced to what this app decides from. The JWS
/// travels alongside the decoded fields: the device reads the fields to decide
/// what to show, the server reads the JWS to decide what to spend, and neither
/// trusts the other's reading.
public struct SubscriptionTransaction: Sendable, Equatable {
    public let id: UInt64
    public let productID: String

    /// When the current period ends. Mandatory: a verified transaction without
    /// an expiry is not promoted into this type, because treating a missing
    /// expiry as forever would turn a malformed StoreKit value into a permanent
    /// entitlement.
    public let expirationDate: Date

    /// Set when Apple refunded or revoked the purchase. Present here at all
    /// because `Transaction.updates` delivers revocations, and a client that
    /// filtered them out would leave the server honouring a refund forever.
    public let revocationDate: Date?

    /// Whether the subscription renews after `expirationDate`.
    ///
    /// `nil` means StoreKit supplied no verified renewal information. It must
    /// stay distinct from `false`: an absent or unverifiable answer is not
    /// evidence that the person cancelled.
    public let willAutoRenew: Bool?

    /// `Transaction.jwsRepresentation`, verbatim, for the server to verify.
    public let jws: String

    /// Whether the local `StoreKit` configuration signed this rather than
    /// Apple (`Transaction.environment == .xcode`). The server verifies a
    /// chain to Apple's root, so it always refuses a locally signed
    /// transaction: that refusal is expected here and a broken money path
    /// anywhere else.
    public let isLocallySigned: Bool

    public init(
        id: UInt64,
        productID: String,
        expirationDate: Date,
        revocationDate: Date?,
        willAutoRenew: Bool? = nil,
        jws: String,
        isLocallySigned: Bool = false
    ) {
        self.id = id
        self.productID = productID
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.willAutoRenew = willAutoRenew
        self.jws = jws
        self.isLocallySigned = isLocallySigned
    }

    /// The tier this transaction grants at `moment`: `.free` for anything
    /// spent, refunded, or bought from a price list this build does not know.
    /// `Transaction.currentEntitlements` already applies most of this; the
    /// checks are repeated here so the rule the app gates on is one a test can
    /// state and a reader can find.
    public func entitledTier(at moment: Date) -> SubscriptionTier {
        guard revocationDate == nil,
              let tier = SubscriptionTier.tier(forProductIdentifier: productID)
        else {
            return .free
        }

        return expirationDate > moment ? tier : .free
    }

    /// What the submission ledger records. The revocation is part of the key:
    /// a refund arrives as the same transaction id with a date on it, and a
    /// ledger keyed on the id alone would skip it as already sent, leaving the
    /// server paying out a refunded subscription.
    public var submissionKey: String {
        revocationDate == nil ? "\(id)" : "\(id).revoked"
    }
}

/// How a purchase attempt ended.
///
/// `pending` is a real outcome rather than a failure: Ask to Buy sends the
/// request to a parent and the answer arrives hours later, through
/// `StoreFront/updates()`, which is exactly why that stream exists.
public enum PurchaseOutcome: Sendable, Equatable {
    case purchased(SubscriptionTransaction)
    case cancelled
    case pending
}

public enum StoreFrontError: LocalizedError, Equatable {
    /// A successful App Store lookup returned no requested product. In the
    /// simulator this means the run scheme is not pointed at `Ond.storekit`; on
    /// a device it means the product is not yet approved in App Store Connect.
    /// Lookup failures remain their original errors so a transient outage does
    /// not masquerade as a product that can never be bought.
    case productUnavailable

    /// `StoreKit` declined to vouch for the signature on a transaction it just
    /// produced. Surfaced rather than swallowed: it should never happen, and a
    /// silent "purchase did nothing" is the worst possible way to find out.
    case unverified

    /// Without this conformance `localizedDescription` bridges to a bare
    /// `NSError`, so the log line that records a failed purchase says "The
    /// operation couldn't be completed" and names neither case.
    public var errorDescription: String? {
        switch self {
        case .productUnavailable: "the App Store has no such product"
        case .unverified: "StoreKit would not verify the transaction"
        }
    }
}

/// Everything this app needs from `StoreKit`, and nothing else. A seam so the
/// decision logic over transactions runs without a signed-in App Store account
/// or a booted simulator; `StoreKitStoreFront` is the only type in the
/// repository that imports `StoreKit`.
public protocol StoreFront: Sendable {
    /// Both cadences, for the prices on the paywall. Empty rather than
    /// throwing — the paywall has a story for a missing price, and a person with
    /// no signal should still be able to read what the subscription is.
    func products() async -> [SubscriptionProduct]

    /// What `StoreKit` currently considers this person entitled to. Answered
    /// from the device, so it works offline, which is why no screen ever waits
    /// on the server for this.
    func currentEntitlements() async -> [SubscriptionTransaction]

    /// Transactions arriving after launch: a renewal, a purchase made on
    /// another device, an Ask to Buy approval, a refund, or the crossgrade
    /// Apple issues when somebody moves between the two cadences.
    func updates() -> AsyncStream<SubscriptionTransaction>

    /// Buys `plan`. Both products sit in one App Store subscription group, so
    /// buying one while holding the other is a change of plan, not a second
    /// subscription: Apple prorates, cancels the old one, and issues a fresh
    /// transaction naming the new product.
    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome

    /// Restores purchases, which App Review requires a paywall to offer. It
    /// prompts for the App Store password, so it is only ever called from a
    /// button somebody pressed.
    func restore() async throws
}
