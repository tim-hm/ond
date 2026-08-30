//! Business logic — decides what a verified transaction is worth, and converts
//! both ways across the proto boundary.
//!
//! Receives explicit dependencies (`&PgPool`, `&dyn TransactionVerifier`), never
//! `Arc<AppState>`, and contains zero raw queries.

use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;

use super::errors::EntitlementError;
use super::metrics;
use super::repository::{self, EntitlementRow, TransactionHolder};
use super::types::{Census, Entitlement, SubscriptionTier, Tier};
use super::verifier::{StoreEnvironment, TransactionVerifier, VerifiedTransaction};
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// The largest token this server will look at. A real `jwsRepresentation` is
/// a few kilobytes; without a bound the only ceiling is tonic's 4 MiB decode
/// limit, and every byte under it is split, base64-decoded three times and
/// JSON-parsed before anything rejects it, on a path with no rate limit. The
/// caller chooses that size, so this layer chooses the maximum.
const MAX_SIGNED_TRANSACTION_BYTES: usize = 8 * 1024;

/// How long a transaction stays put once an identity has claimed it. A reinstall
/// needs the binding to move; there is no account recovery. A rotation needs it
/// not to move freely: the assistant allowance is per user per UTC day, so a
/// token handed round self-minted identities would draw a fresh day's spend at
/// each stop. A day is the allowance's own unit.
const TRANSFER_COOLDOWN: Duration = Duration::days(1);

/// Verifies a submitted transaction and stores what it grants. Three outcomes,
/// only the first an error: not verified; verified and revoked, which is a
/// refund rather than a failure; verified and entitling. Nothing asks whether
/// the caller signed in. The durable anchor is the App Store account: Restore
/// Purchases resubmits the same token and [`claim`] moves the entitlement.
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

    // TODO(2026-11-30): decide at the App Store release whether this stays.
    // The volume is on `ond_entitlement_purchases_total{environment}`, counted
    // just below.

    // `debug`, and the level is the decision: this fires once per cold
    // launch per sandbox subscriber, and nothing irreversible happened. Kept
    // because a sandbox purchase is free and renews fast, so during a beta
    // "how much honoured is not real money" is a live `RUST_LOG` question;
    // persisting past the beta means `StoreEnvironment`'s tightening is overdue.
    if transaction.environment != StoreEnvironment::Production {
        tracing::debug!(
            feature = "entitlement",
            environment = transaction.environment.as_str(),
            "honoured a non-production App Store transaction"
        );
    }

    let revoked = transaction.revoked_at;
    let stored = match revoked {
        Some(revoked_at) => revoke(pool, user_id, &transaction, revoked_at).await?,
        None => claim(pool, user_id, &transaction, now).await?,
    };

    // After the writes, so this counts what was stored rather than what
    // reached the verifier. A revocation is deliberately not a purchase:
    // both arms used to fall through to `Honoured`, so every refund read as
    // a sale on the dashboard. The environment counter stays on the purchase
    // alone — a refund is not an answer to "are these real subscribers".
    if revoked.is_some() {
        metrics::verification(metrics::Verification::Revoked);
    } else {
        metrics::verification(metrics::Verification::Honoured);
        metrics::honoured_environment(transaction.environment.as_str());
    }

    Ok(pb::SubmitAppStoreTransactionResponse {
        entitlement: Some(to_proto(Entitlement::from_row(&stored, now))),
    })
}

/// Grants the purchase, having established that this caller may hold it. A
/// signed transaction names no önd identity, so a copied token entitles whoever
/// sends it unless the server binds it on first claim. The revocation check runs
/// first, keyed by `transactionId`, so one period's refund cannot blacklist a
/// later renewal, and a refunded submission reads the caller's own entitlement.
async fn claim(
    pool: &PgPool,
    user_id: UserId,
    transaction: &VerifiedTransaction,
    now: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    if repository::transaction_was_revoked(
        pool,
        &transaction.transaction_id,
        &transaction.original_transaction_id,
        transaction.signed_at,
    )
    .await?
    {
        return repository::find_entitlement(pool, user_id).await;
    }

    let held_by_another =
        repository::find_transaction_holder(pool, &transaction.original_transaction_id)
            .await?
            .filter(|holder| holder.user_id != user_id);

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
            from = %holder.user_id.support_reference(),
            to = %user_id.support_reference(),
            "moved an App Store transaction to a new identity"
        );

        repository::release_transaction(pool, holder.user_id).await?;
    }

    // Not one statement with the release above: the client resubmits on every
    // launch, so the worst a crash in between can do is leave the purchase
    // unclaimed until the next submission re-grants it — which is cheaper than
    // the deferrable constraint an atomic hand-over would need.
    repository::apply_transaction(
        pool,
        user_id,
        &transaction.transaction_id,
        &transaction.original_transaction_id,
        transaction.tier,
        transaction.expires_at,
        transaction.signed_at,
    )
    .await
}

/// Whether a transaction may leave the identity currently holding it. Both
/// conditions guard money: a holder with no grant was refunded — the tier is
/// cleared on revocation, the binding is not — so a refunded transaction
/// never moves, which stops a refund being escaped under a fresh UUID. The
/// cooldown stops the same token walking a chain of identities.
fn may_transfer(holder: &TransactionHolder, now: DateTime<Utc>) -> bool {
    holder.granted
        && holder
            .claimed_at
            .is_none_or(|claimed_at| now - claimed_at >= TRANSFER_COOLDOWN)
}

/// Records the refund durably and ends the entitlement only when this exact
/// transaction is still the row's current payment. `originalTransactionId`
/// deliberately does not decide the clear: it names the whole lineage, and a
/// late refund for one period must leave a later renewal alone.
async fn revoke(
    pool: &PgPool,
    user_id: UserId,
    transaction: &VerifiedTransaction,
    revoked_at: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    repository::apply_revocation(
        pool,
        user_id,
        &transaction.transaction_id,
        &transaction.original_transaction_id,
        revoked_at,
        transaction.signed_at,
    )
    .await
}

/// What the caller may use, right now — the one decision that must not be
/// the client's: resolved from the caller's own row against the clock, never
/// from a field on a request. `Free` for somebody who bought nothing, and the
/// same for a subscription that lapsed overnight — nothing runs in between.
pub async fn tier(pool: &PgPool, user_id: UserId) -> Result<Tier, EntitlementError> {
    let stored = repository::find_entitlement(pool, user_id).await?;

    Ok(Entitlement::from_row(&stored, Utc::now()).tier())
}

/// Refuses a caller who does not hold `required` — the shape every gated RPC
/// but the assistant's should use (the assistant's decision is a `Claim`, not
/// a yes or no). Here rather than in each handler so "which tier does this
/// cost" is asked one way; `refusal` is the calling feature's own sentence,
/// because the client renders it and only that feature knows the context.
pub async fn require(
    pool: &PgPool,
    user_id: UserId,
    required: Tier,
    refusal: &'static str,
) -> Result<(), EntitlementError> {
    if tier(pool, user_id).await? < required {
        return Err(EntitlementError::Unentitled(refusal));
    }

    Ok(())
}

/// The population, and what it is worth per month. Read through
/// [`super::cache::CensusCache`] by the entitlement metrics handler. It lives
/// here because "how many people are paying" is the same kind of judgement as
/// the rest of this file — the alternative was a second definition of
/// *subscribed* out of reach of the type system and of every test.
pub async fn census(pool: &PgPool) -> Result<Census, EntitlementError> {
    let counted = repository::census(pool).await?;

    Ok(Census {
        users: counted.users,
        plus: counted.plus,
        gross_mrr_usd: monthly_revenue_usd(counted.plus),
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
fn monthly_revenue_usd(plus: i64) -> f64 {
    plus as f64 * SubscriptionTier::Plus.monthly_price_usd()
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
            user_id: UserId(Uuid::nil()),
            granted,
            claimed_at,
        }
    }

    fn instant(seconds: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(seconds, 0).expect("a valid instant")
    }

    /// The rule that decides whether a purchase can be used by somebody other
    /// than whoever first claimed it — the whole of what a copied
    /// `jwsRepresentation` is worth. Asserted here because the clock is a
    /// parameter. The `None` case is rows bound before the column existed:
    /// they read as claimed long ago, so the migration strands nobody.
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
