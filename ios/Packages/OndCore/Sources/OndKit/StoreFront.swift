import Foundation

/// The free trial attached to a subscription, and whether this person can still
/// take it.
///
/// Only free trials are modelled. `StoreKit` also offers pay-up-front and
/// pay-as-you-go introductory offers, and this app sells neither — a type that
/// could express them would be a paywall branch nothing ever takes, and copy
/// nobody would ever proofread.
public struct IntroductoryOffer: Sendable, Equatable {
    /// How long the trial runs, in days. Rendered rather than computed from:
    /// "Try 7 days free" is the sentence, and App Review's 3.1.2 disclosure
    /// needs the same number beside the price that follows it.
    public let trialDays: Int

    /// Whether *this* Apple ID may still take it.
    ///
    /// One trial per Apple ID per subscription group, ever — so somebody who
    /// subscribed last year and lapsed is offered the price, not the trial, and
    /// every piece of trial copy has to branch on this. Answered by `StoreKit`
    /// from the account rather than from anything this app stores.
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

/// One of the subscriptions this app sells, in the vocabulary of the app rather
/// than of `StoreKit`.
///
/// Only what a paywall draws. The `Product` type carries a dozen more fields —
/// subscription group, promotional offers, renewal info — and every one of them
/// would be a reason for a view to reach past this boundary.
public struct SubscriptionProduct: Sendable, Equatable {
    /// Which cadence this is billed at. The identity of the product, because
    /// both of them grant the same tier.
    public let plan: SubscriptionPlan

    /// Already formatted for the storefront the person is buying from. Never
    /// composed here: the App Store owns the currency, the symbol's position,
    /// and whether the amount rounds — and it varies by country.
    public let displayPrice: String

    /// The same amount as a number, for the one thing a formatted string cannot
    /// answer: how much the year saves against twelve months.
    ///
    /// Never rendered. Composing a price from this would put a currency symbol
    /// in the wrong place in half the world, which is exactly what
    /// [`displayPrice`] exists to prevent — this is only ever divided by
    /// another one of itself, and a ratio has no currency.
    public let price: Decimal

    /// The trial on offer, or `nil` where this build's product carries none.
    /// Absent and ineligible are deliberately different: one is a product
    /// without a trial, the other a person who has already had theirs.
    public let introductoryOffer: IntroductoryOffer?

    /// Which tier buying this grants. Never `.free`.
    public var tier: SubscriptionTier {
        plan.tier
    }

    /// - Parameters:
    ///   - plan: which cadence this is, and the product's identity here.
    ///   - displayPrice: the App Store's own formatted string, never composed.
    ///   - price: the same amount as a number, for ratios only.
    ///   - introductoryOffer: the trial, defaulted to none so a caller with
    ///     nothing to say about one says the safe thing.
    public init(
        plan: SubscriptionPlan,
        displayPrice: String,
        price: Decimal,
        introductoryOffer: IntroductoryOffer? = nil
    ) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.price = price
        self.introductoryOffer = introductoryOffer
    }
}

/// One `StoreKit` transaction, reduced to what this app decides from.
///
/// The JWS travels alongside the decoded fields rather than instead of them:
/// this device reads the fields to decide what to show, and the server reads the
/// JWS to decide what to spend. Neither trusts the other's reading, which is the
/// whole arrangement.
public struct SubscriptionTransaction: Sendable, Equatable {
    public let id: UInt64
    public let productID: String

    /// When the current period ends.
    ///
    /// Mandatory because every product this store front represents is a
    /// subscription. A verified transaction without one is not promoted into
    /// this domain type: treating a missing expiry as forever would turn a
    /// malformed or newly shaped StoreKit value into a permanent entitlement.
    public let expirationDate: Date

    /// Set when Apple refunded or revoked the purchase. Present here at all
    /// because `Transaction.updates` delivers revocations, and a client that
    /// filtered them out would leave the server honouring a refund forever.
    public let revocationDate: Date?

    /// `Transaction.jwsRepresentation`, verbatim, for the server to verify.
    public let jws: String

    /// Whether the local `StoreKit` configuration signed this, rather than
    /// Apple (`Transaction.environment == .xcode`).
    ///
    /// The server verifies a chain to Apple's root, so a locally signed
    /// transaction is *always* refused — that rejection is a dev build working
    /// as designed, and everything reading a refusal keys its alarm off this:
    /// expected here, the money path broken anywhere else.
    public let isLocallySigned: Bool

    public init(
        id: UInt64,
        productID: String,
        expirationDate: Date,
        revocationDate: Date?,
        jws: String,
        isLocallySigned: Bool = false
    ) {
        self.id = id
        self.productID = productID
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.jws = jws
        self.isLocallySigned = isLocallySigned
    }

    /// What this transaction entitles somebody to at `moment`, which is `.free`
    /// for anything spent, refunded, or bought from a price list this build does
    /// not know.
    ///
    /// `Transaction.currentEntitlements` has already applied most of this, so
    /// the checks look redundant — they are not. This is the rule the app gates
    /// on, and a rule that lives only inside a framework is one no test can
    /// state and no reader can find.
    public func entitledTier(at moment: Date) -> SubscriptionTier {
        guard revocationDate == nil,
              let tier = SubscriptionTier.tier(forProductIdentifier: productID)
        else {
            return .free
        }

        return expirationDate > moment ? tier : .free
    }

    /// What the submission ledger records.
    ///
    /// The revocation is part of the key, not just the id: a refund arrives as
    /// the *same* transaction with a date on it, and a ledger keyed on the id
    /// alone would skip it as already sent — leaving the server paying out a
    /// subscription Apple has refunded.
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

/// Everything this app needs from `StoreKit`, and nothing else.
///
/// A seam for the same reason `assistant::ModelClient` is one on the server: the
/// interesting logic is what the app *decides* from a set of transactions, and
/// none of that should need a signed-in App Store account and a booted simulator
/// to exercise. `StoreKitStoreFront` is the only type in the repository that
/// imports `StoreKit`.
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

    /// Buys `plan`.
    ///
    /// Buying one while holding the other is an ordinary change of plan rather
    /// than a second subscription, because both products sit in one App Store
    /// subscription group: Apple prorates it, cancels the old one, and issues a
    /// fresh transaction naming the new product. Nothing here has to know that
    /// beyond passing the plan through.
    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome

    /// Restores purchases, which App Review requires a paywall to offer. It
    /// prompts for the App Store password, so it is only ever called from a
    /// button somebody pressed.
    func restore() async throws
}
