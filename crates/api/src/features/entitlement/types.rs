//! What a purchase is worth, once somebody has made one.

use chrono::{DateTime, Utc};

/// What a person may use. Ordered, and the ordering is the type's job: every
/// tier contains the one below, so every gate reads `>= Tier::Plus` and a new
/// tier changes no comparison. No `Unknown`: everything uncertain — an
/// unreachable database, a failed verification, an unheard-of product id —
/// resolves to `Free`, the only safe direction when the gate costs money.
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
/// somebody can buy. Separate from [`Tier`] on purpose: `Free` is not a
/// subscription, and a column typed `Tier` would admit a row claiming a free
/// subscription that expires — this type is what keeps that impossible.
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
    /// List price of one month, in US dollars — the fourth copy of this
    /// number (`Ond.storekit`, App Store Connect, the paywall) and nothing
    /// reconciles them; a stale price only wrongs one panel. Tier is stored,
    /// cadence is not, so a year at $14.99 counts as a month at $1.99. Only
    /// an estimate: Apple keeps 15–30%, tax comes off, refunds are invisible.
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

/// What the server believes about one person, at one moment. Derived on read,
/// so a lapsed subscription answers `Free` with nothing having run in between
/// — there is no renewal job and no expiry sweep. One private field holds
/// both halves or neither, so "önd+ with no expiry" and "Free with one" are
/// states this type cannot hold and no caller has to be trusted about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Entitlement {
    /// The subscription if it is still running, `None` otherwise. A lapsed pair
    /// is dropped here rather than carried on: it is exactly the fact that makes
    /// the tier `Free`, and keeping it would invite a client to render an expiry
    /// for something nobody holds.
    active: Option<(SubscriptionTier, DateTime<Utc>)>,
}

impl Entitlement {
    /// Reads a stored subscription against a clock. Takes the two columns as
    /// stored — both present or both null, per `users_subscription_is_whole`
    /// — and treats any other combination as no subscription, which makes the
    /// return type unable to express the half-written state. `now` is a
    /// parameter so one request resolves everything against a single instant.
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

    /// The row as stored, read against a clock — the one place the two
    /// columns are put together. On the domain type because two features read
    /// the row: this one for `GetEntitlement`, `assistant` to spend a model
    /// call. A second spelling of the pairing would be a second place to find
    /// when "active" comes to mean something more — a grace period, say.
    pub fn from_row(row: &super::repository::EntitlementRow, now: DateTime<Utc>) -> Self {
        debug_assert!(
            row.transaction_id.is_none() || row.original_transaction_id.is_some(),
            "an individual App Store transaction must belong to a subscription lineage"
        );
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
    /// at the exact expiry instant, and every stored value comes from Apple
    /// to the millisecond. The lapsed side also pins that the date goes with
    /// the tier — the one thing a caller could otherwise read and render.
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
