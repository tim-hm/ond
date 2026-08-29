import Foundation

/// What this person may use. `Comparable` is the type's job: every gate reads
/// `tier >= .plus`, so a tier added above `plus` changes no comparison. It
/// agrees on ordering with the proto's `EntitlementTier` and the server's
/// `Tier`. Raw values are written out because they are a stored cache key:
/// reordering must not promote anybody, and a stale `2` reads as `.free`.
public enum SubscriptionTier: Int, Sendable, Comparable, Codable, CaseIterable {
    /// The whole app as it runs on this device: every exercise and moment,
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
    /// Shared by `SubscriptionStore` and `WatchHandoffInbox` because the
    /// subtlety is the whole of it: `integer(forKey:)` answers `0` for a
    /// missing key, and a stale `2` from the three-tier build fails
    /// `init(rawValue:)` — both land on `.free`, and a refresh corrects it.
    public static func cached(in defaults: UserDefaults, forKey key: String) -> Self {
        Self(rawValue: defaults.integer(forKey: key)) ?? .free
    }

    /// What the assistant costs — the one line that opens or closes it. It has
    /// a server half, and the two must move together: `daily_model_calls` in
    /// `features/assistant/types.rs`. Closing only the server leaves the app
    /// showing a chat the server refuses — the "ask again later, forever" loop
    /// that has already happened on a real device. Close the client first.
    public static let assistant: Self = .plus

    /// What a technique behind `requires_subscription` costs. The contract
    /// carries a boolean, so this names the tier it means, once. Reachable only
    /// in tests today — the seed sets the flag false everywhere — but the
    /// machinery prices any technique that ever costs to serve. A seed edit
    /// needs `mise run generate`, or the bundled catalogue disagrees with the server.
    public static let catalogue: Self = .plus

    /// What the leaderboards cost. A board is a fold across every user the
    /// server holds, so it is on the paid side of the line. The server half,
    /// `get_leaderboard` in `features/journey/handlers/`, refuses
    /// `PERMISSION_DENIED`; this constant draws the locked state instead of
    /// letting somebody ask and be refused.
    public static let leaderboards: Self = .plus

    /// What reading health trends costs — the reads only. Writing Mindful
    /// Minutes and a mood back to HealthKit stays free at every tier: a lapsed
    /// subscription must not hold somebody's own data hostage. Enforced only on
    /// this device, by decision: a HealthKit read is local, so there is no
    /// server call to refuse; `assistant` covers the coach's model call.
    public static let healthTrends: Self = .plus

    /// What the phone and the wrist working together costs. Exactly two things
    /// are gated: a session ordered from the phone onto the wrist, and the live
    /// pulse drawn back. Breathing on the watch stays free and standalone, and
    /// the handoff channel is never gated — the tier travels on it. Both halves
    /// are one guard, `WatchHandoffOutbox.place`; the server is not in the path.
    public static let watchConnected: Self = .plus
}

/// The two cadences önd+ is sold at: one subscription, two prices. Both live
/// in one App Store subscription group, so moving between them is Apple's
/// problem: a person holds at most one, Apple prorates the switch, and a
/// crossgrade arrives as an ordinary transaction. Separate from
/// [`SubscriptionTier`] because a cadence is not a rung anything gates on.
public enum SubscriptionPlan: String, Sendable, Equatable, Codable, CaseIterable {
    /// $1.99 a month.
    case monthly

    /// $14.99 a year — the one a paywall badges with its saving, computed from
    /// the two prices the App Store answers with rather than written down here.
    case yearly

    /// The App Store product that buys this plan. Must match `Ond.storekit`,
    /// `PRODUCTS` in the server's `features/entitlement/verifier/appstore.rs`,
    /// and App Store Connect; nothing checks that at build time. The monthly
    /// `2` exists because App Store Connect reserves a deleted product id
    /// forever — the original monthly id can never be used again.
    public var productIdentifier: String {
        switch self {
        case .monthly: "xyz.holmie.ond.plus.monthly2"
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
