import Foundation

/// What this person may use.
///
/// `Comparable`, and that is the type's job: every gate in the app reads
/// `tier >= .plus` rather than enumerating which tiers qualify, so a tier added
/// above `coach` changes no comparison anywhere. It mirrors `EntitlementTier` in
/// the proto and `Tier` on the server, and the three agree on the ordering
/// rather than on a shared representation.
///
/// The raw value is a stored key — the tier is cached across launches so the
/// first frame after a cold start shows the right thing — and it is written out
/// rather than synthesised so reordering the cases cannot silently promote
/// somebody.
public enum SubscriptionTier: Int, Sendable, Comparable, Codable, CaseIterable {
    /// Everything, while the featureset settles — see [`assistant`] and
    /// [`catalogue`] for what the two rungs above would take back.
    case free = 0

    /// What a gated technique would cost. Nothing is gated: [`catalogue`] is
    /// the constant that decides, and `requires_subscription` in the server's
    /// seed is false throughout.
    case plus = 1

    /// What the assistant would cost. It costs nothing: [`assistant`] is the
    /// constant that decides.
    case coach = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The App Store product that buys this tier, or `nil` for the one nobody
    /// buys.
    ///
    /// These ids have to match `ios/Ond/Ond.storekit`, `PRODUCTS` in the
    /// server's `features/entitlement/verifier/appstore.rs`, and App Store
    /// Connect. Nothing checks that they agree at build time, and a mismatch
    /// presents as a paywall with no price and a purchase the server refuses.
    public var productIdentifier: String? {
        switch self {
        case .free: nil
        case .plus: "xyz.holmie.ond.plus.monthly"
        case .coach: "xyz.holmie.ond.coach.monthly"
        }
    }

    /// The tier a product id buys, or `nil` for one this build does not sell.
    ///
    /// `nil` rather than `.free`, because they are different facts: a product
    /// this app has never heard of is a transaction to ignore, not a person to
    /// downgrade. Whoever asks decides which of those it is.
    public static func tier(forProductIdentifier identifier: String) -> Self? {
        purchasable.first { $0.productIdentifier == identifier }
    }

    /// The tiers somebody can buy, cheapest first — the order a paywall lists
    /// them in, derived from the ladder rather than written out beside it.
    ///
    /// A stored `let` rather than a computed property: it is read per
    /// transaction and per paywall pass, and a compile-time-constant list has no
    /// business allocating each time. `allCases` is already in declaration
    /// order, which is the ladder, so there is nothing to sort.
    public static let purchasable: [Self] = allCases.filter { $0 > .free }

    /// What the assistant costs.
    ///
    /// `.free` while the featureset settles — everything the app does is
    /// available to everybody, and what belongs behind a subscription is a
    /// question to answer from how the app gets used rather than ahead of it.
    ///
    /// A named requirement rather than a `.coach` written into the Coach tab,
    /// because a hardcoded tier is a gate you have to find again: this is the
    /// one line that opens or closes the assistant, and every surface that
    /// mentions it reads this. The gates themselves are untouched and still
    /// compare — `tier >= .assistant` is trivially true today and is the same
    /// expression that binds the day this says `.coach` again.
    ///
    /// **It has a server half, and the two must move together.**
    /// `daily_model_calls` in `features/assistant/types.rs` decides whether a
    /// tier buys a model call at all, and nothing but this comment binds them.
    /// Closing only the server leaves this app showing the chat to somebody the
    /// server then refuses — the "ask again later, forever" loop that
    /// `CHAT_SUBSCRIPTION_REPLY` exists because of, and which has already
    /// happened once on a real device. Close the client first, or both at once.
    public static let assistant: Self = .free

    /// What a technique behind `requires_subscription` costs.
    ///
    /// The contract carries a boolean rather than a tier, because there is one
    /// paid catalogue and no plan for a second — so somebody has to say which
    /// tier that boolean means, and it is said here rather than at each of the
    /// two places a technique is decoded (the wire, and the bundled seed).
    ///
    /// Reachable today only in tests: the seed sets `requires_subscription`
    /// false for every technique, so nothing decodes to this. That makes this
    /// half of the catalogue lever, and the boolean the other half — flipping
    /// the seed alone is what re-closes it, and this decides at what price.
    ///
    /// Lever one has a build step the other does not: `catalogue.json` is
    /// generated from the seed by `mise run generate`, so a seed edit that is
    /// not regenerated leaves the bundled copy disagreeing with the server.
    public static let catalogue: Self = .plus
}
