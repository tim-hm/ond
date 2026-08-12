//! Entitlement SQL — five columns on `users`, and one table that deliberately
//! is not on `users` at all.
//!
//! The row's existence is `crate::identity`'s business, which is why nothing
//! here inserts one. `revoked_transactions` is the exception to the shape
//! rather than to the rule: a refund is a fact about a purchase, and filing it
//! on the person's row made it erasable by the person it constrains
//! (`0016_revoked_transactions.sql`).

use chrono::{DateTime, Utc};
use sqlx::PgPool;

use super::errors::EntitlementError;
use super::types::SubscriptionTier;
use crate::identity::UserId;

/// The subscription columns of one `users` row.
pub struct EntitlementRow {
    /// Which product the row holds, whether or not it has run out. `None`
    /// exactly when `subscription_until` is `None`, which the
    /// `users_subscription_is_whole` constraint guarantees.
    pub subscription_tier: Option<SubscriptionTier>,

    /// When it ends, whether or not it already has. The distinction the schema
    /// keeps is between a null and a past date, and reading a past date back is
    /// what lets an expiry be honoured without a job that clears it.
    pub subscription_until: Option<DateTime<Utc>>,

    /// The subscription this row is currently living on, which is what makes a
    /// revocation attributable to it.
    pub original_transaction_id: Option<String>,
}

/// Who holds one App Store transaction, and on what terms.
///
/// Read before a purchase is written, because a transaction is bound to a single
/// identity and this is the row that says which — see
/// `service::claim`.
pub struct TransactionHolder {
    /// Typed rather than a bare `Uuid` because the caller's whole question is
    /// whether this is somebody else, and a comparison against a `Uuid` accepts
    /// any id in scope.
    pub user_id: UserId,

    /// Whether the holder still has a grant from this transaction. `false` means
    /// it was revoked: a refund clears the tier and the expiry while leaving the
    /// binding, so a refunded transaction is frozen to the identity that was
    /// refunded and cannot be carried anywhere else.
    pub granted: bool,

    /// When this holder claimed it. `None` for a row bound before the column
    /// existed, which reads as "long ago".
    pub claimed_at: Option<DateTime<Utc>>,
}

/// How many people exist, and how many are currently paying for what.
///
/// Whole-table counts rather than one person's row — the only read in this
/// feature that is not keyed by identity, because the dashboard's question is
/// about the population rather than about anybody.
pub struct Census {
    pub users: i64,
    pub plus: i64,
    pub coach: i64,
}

/// Counts the population in one pass.
///
/// "Currently subscribed" is `subscription_until > now()`, which is the same
/// comparison `Entitlement::resolve` makes on a single row. Written twice
/// because one is SQL over every row and the other is Rust over one, and a
/// dashboard that disagreed with the gate about who is paying would be worse
/// than no dashboard.
///
/// A sequential scan on `users`, deliberately un-indexed: it runs once per
/// scrape rather than once per request, and an index maintained on every
/// purchase to save a scan on a table this size is the wrong trade.
pub async fn census(pool: &PgPool) -> Result<Census, EntitlementError> {
    let row = sqlx::query!(
        r#"SELECT
             count(*) AS "users!",
             count(*) FILTER (
               WHERE subscription_tier = 'PLUS' AND subscription_until > now()
             ) AS "plus!",
             count(*) FILTER (
               WHERE subscription_tier = 'COACH' AND subscription_until > now()
             ) AS "coach!"
           FROM users"#
    )
    .fetch_one(pool)
    .await?;

    Ok(Census {
        users: row.users,
        plus: row.plus,
        coach: row.coach,
    })
}

pub async fn find_entitlement(
    pool: &PgPool,
    user_id: UserId,
) -> Result<EntitlementRow, EntitlementError> {
    let row = sqlx::query_as!(
        EntitlementRow,
        r#"SELECT
            subscription_tier AS "subscription_tier?: SubscriptionTier",
            subscription_until,
            app_store_original_transaction_id AS original_transaction_id
           FROM users
          WHERE id = $1"#,
        user_id.0
    )
    .fetch_optional(pool)
    .await?
    .ok_or(EntitlementError::Missing)?;

    Ok(row)
}

/// Finds the identity a transaction is bound to, if any identity is.
///
/// At most one row can answer, which the
/// `users_app_store_original_transaction_id_key` constraint is what guarantees.
pub async fn find_transaction_holder(
    pool: &PgPool,
    original_transaction_id: &str,
) -> Result<Option<TransactionHolder>, EntitlementError> {
    let holder = sqlx::query_as!(
        TransactionHolder,
        r#"SELECT
            id AS "user_id: UserId",
            subscription_tier IS NOT NULL AS "granted!",
            subscription_claimed_at AS claimed_at
           FROM users
          WHERE app_store_original_transaction_id = $1"#,
        original_transaction_id
    )
    .fetch_optional(pool)
    .await?;

    Ok(holder)
}

/// Records that Apple has revoked a transaction, for as long as this database
/// exists.
///
/// Outside the `users` row on purpose, and the only write in this feature that
/// is: every other defence against a refunded transaction being replayed lives
/// on the row it was granted against, and `DeleteAccount` deletes that row. What
/// is written here survives an erasure, a merge, and a reinstall — none of which
/// is a reason for Apple's money to come back.
///
/// `DO NOTHING` rather than `DO UPDATE`: the client resubmits whatever
/// `StoreKit` hands it on every launch, so the same revocation arrives
/// repeatedly and the first arrival is the closest thing to the truth this
/// server will see. Updating would let a resubmission years later re-date a
/// refund that happened once.
pub async fn record_revocation(
    pool: &PgPool,
    original_transaction_id: &str,
    revoked_at: DateTime<Utc>,
) -> Result<(), EntitlementError> {
    sqlx::query!(
        "INSERT INTO revoked_transactions (original_transaction_id, revoked_at)
         VALUES ($1, $2)
         ON CONFLICT (original_transaction_id) DO NOTHING",
        original_transaction_id,
        revoked_at
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// When Apple revoked this transaction, if it ever did.
///
/// One primary-key lookup, asked before anything is granted. The date rather
/// than a yes/no, because `originalTransactionId` names a whole subscription
/// lineage rather than one payment: a refund of one period must not blacklist
/// the renewals that follow it, and the date is what tells the two apart — see
/// `service::claim`.
pub async fn revoked_at(
    pool: &PgPool,
    original_transaction_id: &str,
) -> Result<Option<DateTime<Utc>>, EntitlementError> {
    let revoked_at = sqlx::query_scalar!(
        "SELECT revoked_at FROM revoked_transactions WHERE original_transaction_id = $1",
        original_transaction_id
    )
    .fetch_optional(pool)
    .await?;

    Ok(revoked_at)
}

/// Writes what one verified transaction says onto the row, returning the row as
/// stored.
///
/// The single write path, and a revocation goes through it with `grant` set to
/// `None` — because a refund is not a different kind of write, it is a
/// transaction that happens to grant nothing. One statement therefore carries
/// the whole rule:
///
/// - **The row moves together**, because the tier and the expiry describe one
///   purchase. An upgrade from Plus to Coach mid-month issues a Coach
///   transaction whose expiry is *earlier* than the Plus period it replaced, so
///   a rule that kept the later expiry — which is what M8 did, with `GREATEST` —
///   would leave somebody paying for Coach and holding Plus.
/// - **Only forwards**, because the client resubmits whatever `StoreKit` hands
///   it and `Transaction.updates` and `currentEntitlements` have no ordering
///   between them. `signedDate` is the one field that orders them correctly:
///   Apple signs the truth at a moment, and the most recently signed transaction
///   for a subscription group is that group's current state.
///
/// A revocation therefore leaves `subscription_signed_at` set to its own
/// `signedDate` rather than nulling it. Nulling it reopened the guard to *any*
/// signedDate, including the pre-refund transaction the client still holds and
/// which verifies perfectly — its payload carries no `revocationDate` — so a
/// refund could be undone by resubmitting the purchase it refunded. The one
/// statement that does null it is [`release_transaction`], which gives up the
/// binding as well and so leaves nothing for a stale submission to win against.
///
/// `subscription_claimed_at` moves with every write, revocations included. That
/// costs nothing: it gates transfers, and a revoked transaction is not
/// transferable at all.
///
/// A submission that loses the comparison changes nothing and is not an error —
/// it is what a client sending the *same* transaction again gets, which it does
/// on every launch, so it is the ordinary path rather than the exceptional one.
/// That is why the `UNION ALL` is here rather than a second call: the caller has
/// to be told what the row holds either way, and paying two round trips for the
/// common case to save a CTE would be the wrong trade.
pub async fn apply_transaction(
    pool: &PgPool,
    user_id: UserId,
    original_transaction_id: &str,
    grant: Option<(SubscriptionTier, DateTime<Utc>)>,
    signed_at: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    let (tier, until) = grant.unzip();

    let row = sqlx::query_as!(
        EntitlementRow,
        r#"WITH moved AS (
             UPDATE users
                SET subscription_tier = $2,
                    subscription_until = $3,
                    app_store_original_transaction_id = $4,
                    subscription_signed_at = $5,
                    subscription_claimed_at = now(),
                    updated_at = now()
              WHERE id = $1
                AND (subscription_signed_at IS NULL OR subscription_signed_at < $5)
             RETURNING subscription_tier, subscription_until,
                       app_store_original_transaction_id
           )
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id
           FROM moved
           UNION ALL
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id
           FROM users
          WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM moved)"#,
        user_id.0,
        tier as Option<SubscriptionTier>,
        until,
        original_transaction_id,
        signed_at,
    )
    .fetch_optional(pool)
    .await?
    .ok_or(EntitlementError::Missing)?;

    Ok(row)
}

/// Unbinds a transaction from the row holding it, so another identity may claim
/// it.
///
/// Clears the binding and the grant together: half a release would leave a row
/// entitled by a transaction it no longer holds, which is the state
/// [`find_transaction_holder`] reads as a revocation. Whether the release is
/// allowed at all is `service::claim`'s decision.
pub async fn release_transaction(pool: &PgPool, user_id: UserId) -> Result<(), EntitlementError> {
    sqlx::query!(
        r#"UPDATE users
              SET subscription_tier = NULL,
                  subscription_until = NULL,
                  subscription_signed_at = NULL,
                  subscription_claimed_at = NULL,
                  app_store_original_transaction_id = NULL,
                  updated_at = now()
            WHERE id = $1"#,
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(())
}
