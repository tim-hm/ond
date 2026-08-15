import Foundation

/// What this person may use.
///
/// `Comparable`, and that is the type's job: every gate in the app reads
/// `tier >= .plus` rather than enumerating which tiers qualify, so a tier added
/// above `plus` changes no comparison anywhere. It mirrors `EntitlementTier` in
/// the proto and `Tier` on the server, and the three agree on the ordering
/// rather than on a shared representation.
///
/// Two rungs, and the line between them is what a use costs to run: everything
/// that happens on this device is free, and everything önd+ sells is something
/// a server spends on per use. The named constants below are where each of
/// those decisions is written down.
///
/// The raw value is a stored key — the tier is cached across launches so the
/// first frame after a cold start shows the right thing — and it is written out
/// rather than synthesised so reordering the cases cannot silently promote
/// somebody. A cached `2` from the three-tier build fails `init(rawValue:)` and
/// reads as `.free`, corrected by the first refresh.
public enum SubscriptionTier: Int, Sendable, Comparable, Codable, CaseIterable {
    /// The whole app as it runs on this device: every exercise and protocol,
    /// custom exercises, the session player, your journey, and the watch app.
    case free = 0

    /// önd+ — marketing's name for it, and the only thing anybody can buy.
    case plus = 1

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The tier a product id buys, or `nil` for one this build does not sell.
    ///
    /// `nil` rather than `.free`, because they are different facts: a product
    /// this app has never heard of is a transaction to ignore, not a person to
    /// downgrade. Whoever asks decides which of those it is.
    public static func tier(forProductIdentifier identifier: String) -> Self? {
        SubscriptionPlan(productIdentifier: identifier)?.tier
    }

    /// The tier cached under `key`, or `.free` where nothing readable is there.
    ///
    /// Two stores keep this cache — the phone's `SubscriptionStore` and the
    /// wrist's `WatchHandoffInbox` — for the same reason and with the same
    /// hazard: `UserDefaults.integer(forKey:)` answers `0` for a missing key,
    /// which is `.free` and correct, and it answers a stale `2` from the
    /// three-tier build, which `init(rawValue:)` refuses and this reads as
    /// `.free` too. Both directions land on the tier that gives nothing away,
    /// and a refresh corrects it.
    ///
    /// Shared rather than written twice because the subtlety is the whole of
    /// it: the obvious spelling — a raw value trusted straight out of defaults
    /// — is wrong in a way no test on either store would catch.
    public static func cached(in defaults: UserDefaults, forKey key: String) -> Self {
        Self(rawValue: defaults.integer(forKey: key)) ?? .free
    }

    /// What the assistant costs.
    ///
    /// A named requirement rather than a `.plus` written into the Coach tab,
    /// because a hardcoded tier is a gate you have to find again: this is the
    /// one line that opens or closes the assistant, and every surface that
    /// mentions it reads this.
    ///
    /// **It has a server half, and the two must move together.**
    /// `daily_model_calls` in `features/assistant/types.rs` decides whether a
    /// tier buys a model call at all, and nothing but this comment binds them.
    /// Closing only the server leaves this app showing the chat to somebody the
    /// server then refuses — the "ask again later, forever" loop that
    /// `CHAT_SUBSCRIPTION_REPLY` exists because of, and which has already
    /// happened once on a real device. Close the client first, or both at once.
    public static let assistant: Self = .plus

    /// What a technique behind `requires_subscription` costs.
    ///
    /// The contract carries a boolean rather than a tier, and there is only one
    /// paid entitlement — so somebody has to say which tier that boolean means,
    /// and it is said here rather than at each place a technique is decoded (the
    /// wire and the bundled seed).
    ///
    /// Reachable today only in tests: the seed sets `requires_subscription`
    /// false for every technique, and the single-tier collapse is what settled
    /// that the catalogue's *breadth* is not the thing for sale — a session
    /// runs here and costs nobody anything. The machinery stays because it is
    /// the only way to price a technique that ever does cost something to
    /// serve, and this decides at what price.
    ///
    /// Lever one has a build step the other does not: `catalogue.json` is
    /// generated from the seed by `mise run generate`, so a seed edit that is
    /// not regenerated leaves the bundled copy disagreeing with the server.
    public static let catalogue: Self = .plus

    /// What the leaderboards cost.
    ///
    /// A board is a fold across every user the server holds — it cannot be
    /// computed on this device at all — so it is on the paid side of the line.
    /// Its server half is `get_leaderboard` in `features/journey/handlers/`,
    /// which refuses `PERMISSION_DENIED`; this constant is what draws the
    /// locked state instead of letting somebody ask and be refused.
    public static let leaderboards: Self = .plus

    /// What reading health *trends* costs.
    ///
    /// The reads, and only the reads. Writing Mindful Minutes and a mood back
    /// to HealthKit stays free at every tier: it costs nothing to serve, and an
    /// app that stopped filling in somebody's Health app when a subscription
    /// lapsed would be holding their own data hostage. What is sold is the
    /// coach reasoning from a resting rate and an HRV, which is a language
    /// model call with a briefing attached.
    public static let healthTrends: Self = .plus

    /// What the phone and the wrist doing things *together* costs.
    ///
    /// Breathing on the watch is free, standalone, and always was — the
    /// companion has to be genuinely useful on its own or it reads as a shell,
    /// which App Review notices and so does everybody else. What this gates is
    /// the pairing: a session ordered from the phone onto the wrist, the live
    /// pulse the phone draws from it, and the wrist's practice syncing up to
    /// the server. The handoff channel itself is never gated, because the tier
    /// travels on it.
    public static let watchConnected: Self = .plus
}

/// The two cadences önd+ is sold at.
///
/// One subscription, two prices. Both live in one App Store subscription group,
/// which is what makes moving between them Apple's problem rather than this
/// app's: a person holds at most one at a time, Apple prorates the switch, and
/// a crossgrade arrives as an ordinary transaction naming the other product.
///
/// Separate from [`SubscriptionTier`] because they answer different questions —
/// what somebody may use, and what they are billed for. Folding the cadence
/// into the tier would put a rung on a ladder that nothing gates on.
public enum SubscriptionPlan: String, Sendable, Equatable, Codable, CaseIterable {
    /// $1.99 a month.
    case monthly

    /// $14.99 a year — the one a paywall badges with its saving, computed from
    /// the two prices the App Store answers with rather than written down here.
    case yearly

    /// The App Store product that buys this plan.
    ///
    /// These ids have to match `ios/Ond/Ond.storekit`, `PRODUCTS` in the
    /// server's `features/entitlement/verifier/appstore.rs`, and App Store
    /// Connect. Nothing checks that they agree at build time, and a mismatch
    /// presents as a paywall with no price and a purchase the server refuses.
    public var productIdentifier: String {
        switch self {
        case .monthly: "xyz.holmie.ond.plus.monthly"
        case .yearly: "xyz.holmie.ond.plus.yearly"
        }
    }

    /// What buying it grants, which is the same tier either way. The cadence
    /// decides what Apple charges and when; it never decides what opens.
    public var tier: SubscriptionTier {
        .plus
    }

    /// The word for one billing period, as "$1.99 a month" and the renewal
    /// terms both need it. One mapping, because two would eventually disagree
    /// on the same screen.
    public var periodName: String {
        switch self {
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    /// The plan a product id names, or `nil` for one this build does not sell.
    public init?(productIdentifier identifier: String) {
        guard let plan = Self.allCases.first(where: { $0.productIdentifier == identifier })
        else { return nil }

        self = plan
    }
}
