//! Business logic — decides what a verified transaction is worth, and converts
//! both ways across the proto boundary.
//!
//! Receives explicit dependencies (`&PgPool`, `&dyn TransactionVerifier`), never
//! `Arc<AppState>`, and contains zero raw queries.

use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;

use super::errors::EntitlementError;
use super::repository::{self, EntitlementRow, TransactionHolder};
use super::types::{Census, Entitlement, SubscriptionTier, Tier};
use super::verifier::{TransactionVerifier, VerifiedTransaction};
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// The largest token this server will look at.
///
/// A real `jwsRepresentation` is a few kilobytes — three base64 segments, one of
/// which carries Apple's three-certificate chain. Without a bound the only
/// ceiling is tonic's 4 MiB decode limit, and every byte under it is split,
/// base64-decoded three times and JSON-parsed before anything rejects it, on a
/// path with no rate limit in front of it. The caller chooses that size, so this
/// layer chooses the maximum.
const MAX_SIGNED_TRANSACTION_BYTES: usize = 8 * 1024;

/// How long a transaction stays put once an identity has claimed it.
///
/// A reinstall needs the binding to move — with no account recovery, a person
/// who loses their identity would otherwise keep paying for a Coach tier the
/// server no longer believes in. A rotation needs it *not* to move freely: the
/// assistant's allowance is counted per user per UTC day, so a token handed
/// round a group of self-minted identities would draw a fresh day's provider
/// spend at each stop. A day is the unit the allowance itself is counted in, so
/// a rotating token buys no more than the one subscriber it was sold to.
const TRANSFER_COOLDOWN: Duration = Duration::days(1);

/// Verifies a submitted transaction and stores what it grants.
///
/// Three outcomes, and only the first is an error: the token does not verify;
/// the token verifies and revokes; the token verifies and entitles. The middle
/// one is a refund, which is not a failure of anything — the caller is simply
/// not a subscriber any more, and the response says so.
///
/// **Nothing here asks whether the caller has signed in**, and possession of the
/// identity is the whole of the claim exactly as it is everywhere else. An
/// entitlement is keyed on `users.id`, but the durable anchor under a
/// subscription was always the App Store account: somebody arriving on a new
/// phone with a fresh identity taps Restore Purchases, `StoreKit` hands the same
/// signed transaction back, and [`claim`] moves the entitlement onto whoever
/// presents it. Requiring Sign in with Apple first bought none of that recovery
/// and spent a sale on a sheet to buy it.
pub async fn submit_transaction(
    pool: &PgPool,
    verifier: &dyn TransactionVerifier,
    user_id: UserId,
    signed_transaction: &str,
) -> Result<pb::SubmitAppStoreTransactionResponse, EntitlementError> {
    if signed_transaction.len() > MAX_SIGNED_TRANSACTION_BYTES {
        return Err(EntitlementError::TooLarge(MAX_SIGNED_TRANSACTION_BYTES));
    }

    let transaction = verifier.verify(signed_transaction)?;
    let now = Utc::now();

    let stored = match transaction.revoked_at {
        Some(revoked_at) => revoke(pool, user_id, &transaction, revoked_at).await?,
        None => claim(pool, user_id, &transaction, now).await?,
    };

    Ok(pb::SubmitAppStoreTransactionResponse {
        entitlement: Some(to_proto(Entitlement::from_row(&stored, now))),
    })
}

/// Grants the purchase, having first established that this caller may hold it.
///
/// A signed transaction names an Apple account, not an önd identity, and
/// nothing in it says who may submit it — so a token copied off a device
/// entitles whoever sends it unless the server binds it. The binding is made on
/// first claim and enforced by
/// `users_app_store_original_transaction_id_key`; this is where the conflict
/// gets an answer a client can act on rather than the opaque `internal` a
/// constraint violation would produce.
///
/// The revocation check comes first, and is the one rule here that is not about
/// who may hold the purchase but about whether it is still a purchase at all.
/// Every other defence against a refunded token — the surviving binding, the
/// ordering marker — is state on the `users` row it was granted against, and
/// erasure deletes that row; `revoked_transactions` is what a refund leaves
/// behind that nobody can ask to have deleted.
///
/// **Against the revocation's date, not merely its existence.**
/// `originalTransactionId` is stable across every renewal of one subscription,
/// so a row in that table is a fact about a lineage rather than about a payment.
/// Refusing on presence alone would leave somebody who was refunded one period
/// and went on paying — or who resubscribed within the group — permanently Free,
/// with no server-side route back. What the replay defence actually needs is the
/// ordering property the row-level guard has: a transaction signed *before*
/// Apple revoked cannot grant, and one signed after is a purchase that happened
/// afterwards. The pre-refund token is always the former, because nothing is
/// refunded before it is bought.
///
/// Answered with the caller's own entitlement rather than an error, exactly as a
/// submission losing the ordering comparison is: the client resubmits whatever
/// `StoreKit` hands it on every launch, so a refunded transaction arriving is
/// the ordinary path. An error would also tell a stranger submitting a token
/// they found that it had been refunded, which is nobody's business but the
/// buyer's.
async fn claim(
    pool: &PgPool,
    user_id: UserId,
    transaction: &VerifiedTransaction,
    now: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    let revoked_at = repository::revoked_at(pool, &transaction.original_transaction_id).await?;

    if revoked_at.is_some_and(|revoked_at| transaction.signed_at <= revoked_at) {
        return repository::find_entitlement(pool, user_id).await;
    }

    let held_by_another =
        repository::find_transaction_holder(pool, &transaction.original_transaction_id)
            .await?
            .filter(|holder| holder.user_id != user_id.0);

    if let Some(holder) = held_by_another {
        if !may_transfer(&holder, now) {
            return Err(EntitlementError::Claimed);
        }

        // Money changing hands between identities, bounded by the cooldown to a
        // frequency a log can carry: this is the one line that says a purchase
        // is being used by somebody other than whoever first claimed it. Both
        // identities by reference, for the reason `UserId::support_reference`
        // gives.
        tracing::info!(
            feature = "entitlement",
            from = %UserId(holder.user_id).support_reference(),
            to = %user_id.support_reference(),
            "moved an App Store transaction to a new identity"
        );

        repository::release_transaction(pool, UserId(holder.user_id)).await?;
    }

    // Not one statement with the release above: the client resubmits on every
    // launch, so the worst a crash in between can do is leave the purchase
    // unclaimed until the next submission re-grants it — which is cheaper than
    // the deferrable constraint an atomic hand-over would need.
    repository::apply_transaction(
        pool,
        user_id,
        &transaction.original_transaction_id,
        Some((transaction.tier, transaction.expires_at)),
        transaction.signed_at,
    )
    .await
}

/// Whether a transaction may leave the identity currently holding it.
///
/// Both conditions guard money rather than tidiness. A holder with no grant was
/// refunded — the tier is cleared on revocation and the binding is not — so a
/// refunded transaction never moves, which is what stops a refund being escaped
/// by resubmitting under a fresh UUID. The cooldown is what stops the same token
/// walking a chain of identities, one daily allowance at a time.
fn may_transfer(holder: &TransactionHolder, now: DateTime<Utc>) -> bool {
    holder.granted
        && holder
            .claimed_at
            .is_none_or(|claimed_at| now - claimed_at >= TRANSFER_COOLDOWN)
}

/// Ends the entitlement, but only if the refund is for the subscription this
/// row is actually living on.
///
/// The guard matters and is here rather than in the `UPDATE`'s `WHERE` clause
/// because it is a rule rather than a query: `Transaction.updates` delivers a
/// revocation for whatever the person bought, and somebody who cancelled last
/// year's subscription and started a new one must not lose the new one to the
/// old one's refund arriving late.
///
/// The binding survives the revocation, so the refunded transaction stays
/// attributable and stays unusable by anybody else.
///
/// The tombstone is written before that guard rather than after it, because the
/// two answer different questions. Whether *this* row loses its tier depends on
/// which subscription the row is living on; whether the transaction was refunded
/// does not depend on anybody's row at all, and the unrelated-refund case —
/// where the caller does not hold the revoked transaction — is precisely the one
/// where nothing else would record it.
async fn revoke(
    pool: &PgPool,
    user_id: UserId,
    transaction: &VerifiedTransaction,
    revoked_at: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    repository::record_revocation(pool, &transaction.original_transaction_id, revoked_at).await?;

    let stored = repository::find_entitlement(pool, user_id).await?;

    if stored.original_transaction_id.as_deref() != Some(&transaction.original_transaction_id) {
        return Ok(stored);
    }

    repository::apply_transaction(
        pool,
        user_id,
        &transaction.original_transaction_id,
        None,
        transaction.signed_at,
    )
    .await
}

/// What the caller may use, right now.
///
/// The one decision that must not be the client's: `assistant` reads this to
/// know whether a caller may spend a language-model call, so it is resolved from
/// the caller's own row against the clock and never from a field on a request.
/// `Free` for somebody who has bought nothing, and the same for a subscription
/// that lapsed overnight — nothing runs in between to notice.
pub async fn tier(pool: &PgPool, user_id: UserId) -> Result<Tier, EntitlementError> {
    let stored = repository::find_entitlement(pool, user_id).await?;

    Ok(Entitlement::from_row(&stored, Utc::now()).tier())
}

/// The population, and what it is worth per month.
///
/// Read by `obs::metrics` once per scrape. It lives here rather than in the
/// metrics module because "how many people are paying" and "what that comes to"
/// are the same kind of judgement as everything else in this file — and because
/// the alternative was a second definition of *subscribed* written in a
/// Prometheus exporter's YAML, out of reach of the type system and of every test
/// in this crate.
pub async fn census(pool: &PgPool) -> Result<Census, EntitlementError> {
    let counted = repository::census(pool).await?;

    Ok(Census {
        users: counted.users,
        plus: counted.plus,
        coach: counted.coach,
        gross_mrr_usd: monthly_revenue_usd(counted.plus, counted.coach),
    })
}

/// What the subscriptions counted are worth in a month, at list price.
///
/// Gross and nominal: see [`SubscriptionTier::monthly_price_usd`] for everything
/// standing between this and money actually received.
#[allow(
    clippy::cast_precision_loss,
    reason = "a subscriber count past f64's 53-bit mantissa is 9 quadrillion people; money is f64 here and there is nothing to convert through"
)]
fn monthly_revenue_usd(plus: i64, coach: i64) -> f64 {
    plus as f64 * SubscriptionTier::Plus.monthly_price_usd()
        + coach as f64 * SubscriptionTier::Coach.monthly_price_usd()
}

/// What the server believes this caller holds, right now.
///
/// Never an error for somebody who has bought nothing: the client renders a
/// paywall from this answer, so "not subscribed" has to be distinguishable from
/// "the server is unreachable".
pub async fn get_entitlement(
    pool: &PgPool,
    user_id: UserId,
) -> Result<pb::GetEntitlementResponse, EntitlementError> {
    let stored = repository::find_entitlement(pool, user_id).await?;

    Ok(pb::GetEntitlementResponse {
        entitlement: Some(to_proto(Entitlement::from_row(&stored, Utc::now()))),
    })
}

fn to_proto(entitlement: Entitlement) -> pb::Entitlement {
    let tier = match entitlement.tier() {
        Tier::Free => pb::EntitlementTier::Free,
        Tier::Plus => pb::EntitlementTier::Plus,
        Tier::Coach => pb::EntitlementTier::Coach,
    };

    pb::Entitlement {
        tier: tier as i32,
        expires_at: entitlement
            .expires_at()
            .map(crate::wire::timestamp_to_proto),
    }
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;

    fn holder(granted: bool, claimed_at: Option<DateTime<Utc>>) -> TransactionHolder {
        TransactionHolder {
            user_id: Uuid::nil(),
            granted,
            claimed_at,
        }
    }

    fn instant(seconds: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(seconds, 0).expect("a valid instant")
    }

    /// The rule that decides whether a purchase can be used by somebody other
    /// than whoever first claimed it, which is the whole of what a copied
    /// `jwsRepresentation` is worth. Asserted here rather than only through the
    /// wire, because the clock is a parameter and the database is not needed to
    /// move it.
    ///
    /// The `None` case is the rows bound before the column existed: they read as
    /// claimed long ago, so the migration does not strand anybody.
    #[test]
    fn a_transaction_moves_only_after_it_has_settled_and_never_after_a_refund() {
        let now = instant(1_800_000_000);
        let settled = now - TRANSFER_COOLDOWN;

        assert!(may_transfer(&holder(true, Some(settled)), now));
        assert!(may_transfer(&holder(true, None), now));

        assert!(
            !may_transfer(&holder(true, Some(settled + Duration::seconds(1))), now),
            "a token handed round faster than the cooldown draws a fresh daily allowance at each stop"
        );
        assert!(
            !may_transfer(&holder(false, Some(settled)), now),
            "a refunded transaction is frozen to the identity that was refunded"
        );
    }
}
