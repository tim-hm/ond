//! What a purchase is worth, once somebody has made one.

use chrono::{DateTime, Utc};

/// What a person may use.
///
/// Ordered, and the ordering is the type's job: every tier contains the one
/// below it, so every gate in the codebase reads `>= Tier::Plus` rather than
/// enumerating which tiers qualify. Adding a tier above `Plus` then changes no
/// comparison anywhere.
///
/// No `Unknown`. Everything that could make the answer uncertain — an
/// unreachable database, a transaction that failed to verify, a product id this
/// build has never heard of — resolves to `Free`, which is the only safe
/// direction to fail in when the thing being gated costs money.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tier {
    /// Everything that runs on the device, which is most of the app.
    Free,

    /// önd+, and the whole of what it sells is what a use costs this server:
    /// the language model behind the assistant, the leaderboard fold, and the
    /// health trends the coach reads.
    Plus,
}

/// Mirrors the `subscription_tier` Postgres enum, which holds only the tiers
/// somebody can buy.
///
/// Separate from [`Tier`] rather than folded into it, and the separation is the
/// point: `Free` is not a subscription, so a column that could store it would
/// admit a row claiming a free subscription that expires. One label now that
/// there is one product, and the type survives the collapse because it is what
/// keeps that impossible — a column typed `Tier` would admit the free row this
/// one cannot express.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "subscription_tier", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SubscriptionTier {
    Plus,
}

/// The population at one moment, as the dashboard reads it.
///
/// Counts and money together because they are one query and one scrape, and
/// because the revenue figure is meaningless without the count it came from —
/// a panel showing money alone cannot distinguish a price change from a sale.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Census {
    /// Everybody with a row, which for this app means everybody who has ever
    /// opened it: an identity is created on first launch, before any purchase
    /// and without anybody signing up for anything.
    pub users: i64,

    /// Subscriptions that have not run out. One number because there is one
    /// product; the monthly and yearly SKUs are the same subscription bought at
    /// two cadences, and a dashboard splitting them would be reporting billing
    /// rather than subscribers.
    pub plus: i64,

    /// What those subscriptions bill in a month at list price, gross.
    pub gross_mrr_usd: f64,
}

impl SubscriptionTier {
    /// List price of one month, in US dollars.
    ///
    /// The fourth place this number is written down — `ios/Ond/Ond.storekit`,
    /// App Store Connect and the paywall hold the other three — and, like the
    /// product ids in `verifier::appstore`, nothing reconciles them. The
    /// consequence here is milder than a mismatched id, which breaks a purchase:
    /// a stale price makes one dashboard panel wrong and nothing else, which is
    /// why this is a constant rather than a column.
    ///
    /// The monthly list price, for a subscription sold monthly and yearly. The
    /// database records which tier somebody holds and not which cadence they
    /// bought it at, so a year at $14.99 counts here as a month at $1.99 —
    /// understating the yearly buyer's month by a quarter. Correcting it means
    /// storing the product id, which is a column to keep in step with Apple for
    /// one panel's accuracy.
    ///
    /// Only ever an estimate of income, and the dashboard says so where it is
    /// read. Apple keeps 15–30%, storefronts price in their own currency, tax
    /// comes off, and a refund is invisible here until the subscription lapses.
    pub const fn monthly_price_usd(self) -> f64 {
        match self {
            Self::Plus => 1.99,
        }
    }

    /// The label this tier carries on a metric, matching the Postgres enum.
    pub const fn as_metric_label(self) -> &'static str {
        match self {
            Self::Plus => "PLUS",
        }
    }
}

impl From<SubscriptionTier> for Tier {
    fn from(tier: SubscriptionTier) -> Self {
        match tier {
            SubscriptionTier::Plus => Self::Plus,
        }
    }
}

/// What the server believes about one person, at one moment.
///
/// Derived on read rather than stored, so a subscription that lapsed overnight
/// answers `Free` on the next call with nothing having run in between. There is
/// no renewal job and no expiry sweep for the same reason: the only thing that
/// would keep such a job honest is this calculation.
///
/// One private field holding both halves or neither, so "önd+ with no expiry"
/// and "Free with one" are states this type cannot hold and no caller has to be
/// trusted not to construct.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Entitlement {
    /// The subscription if it is still running, `None` otherwise. A lapsed pair
    /// is dropped here rather than carried on: it is exactly the fact that makes
    /// the tier `Free`, and keeping it would invite a client to render an expiry
    /// for something nobody holds.
    active: Option<(SubscriptionTier, DateTime<Utc>)>,
}

impl Entitlement {
    /// Reads a stored subscription against a clock.
    ///
    /// Takes the two columns as they come out of the database — either both
    /// present or both null, which the `users_subscription_is_whole` constraint
    /// guarantees — and treats any other combination as no subscription. That
    /// last part is not defensive clutter: it is what makes the return type
    /// unable to express the half-written state the constraint forbids.
    ///
    /// `now` is a parameter rather than read here so the boundary is testable
    /// and so one request resolves every entitlement it touches against a single
    /// instant.
    fn resolve(
        tier: Option<SubscriptionTier>,
        until: Option<DateTime<Utc>>,
        now: DateTime<Utc>,
    ) -> Self {
        Self {
            active: tier.zip(until).filter(|(_, until)| *until > now),
        }
    }

    pub fn tier(&self) -> Tier {
        self.active.map_or(Tier::Free, |(tier, _)| Tier::from(tier))
    }

    pub fn expires_at(&self) -> Option<DateTime<Utc>> {
        self.active.map(|(_, until)| until)
    }

    /// The row as stored, read against a clock.
    ///
    /// The one place the two columns are put together, and it lives on the
    /// domain type rather than in a service because two features read that row:
    /// this one to answer `GetEntitlement`, and `assistant` to decide whether to
    /// spend a model call. A second spelling of the pairing would be a second
    /// place to find when "active" comes to mean something more — a grace
    /// period, say.
    pub fn from_row(row: &super::repository::EntitlementRow, now: DateTime<Utc>) -> Self {
        Self::resolve(row.subscription_tier, row.subscription_until, now)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instant(seconds: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(seconds, 0).expect("a valid instant")
    }

    /// The expiry is the moment the entitlement ends, not the last moment it
    /// holds: an inclusive comparison would leave a lapsed subscriber on önd+
    /// for as long as the clock reported the exact expiry instant, and every
    /// stored value here comes from Apple to the millisecond.
    ///
    /// The lapsed side also pins that the date goes with the tier, which is the
    /// one thing a caller could otherwise read and render.
    #[test]
    fn the_expiry_instant_is_already_lapsed() {
        let expiry = instant(1_800_000_000);

        let lapsed = Entitlement::resolve(Some(SubscriptionTier::Plus), Some(expiry), expiry);
        assert_eq!(lapsed.tier(), Tier::Free);
        assert_eq!(lapsed.expires_at(), None);

        let live = Entitlement::resolve(
            Some(SubscriptionTier::Plus),
            Some(expiry),
            expiry - chrono::Duration::seconds(1),
        );
        assert_eq!(live.tier(), Tier::Plus);
        assert_eq!(live.expires_at(), Some(expiry));
    }

    /// Every gate in the codebase is a comparison rather than a match, and the
    /// ordering comes from the declaration order of a fieldless enum — so
    /// reordering the variants silently gives the paid features away. Nothing
    /// else would notice.
    #[test]
    fn the_variants_are_declared_cheapest_first() {
        assert!(Tier::Free < Tier::Plus);
    }
}
