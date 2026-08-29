//! Entitlement SQL — six columns on `users`, and two tables that deliberately
//! are not on `users` at all. The row's existence is `crate::identity`'s
//! business, so nothing here inserts one. The revocation tables are the
//! exception to the shape: a refund is a fact about a purchase, and filing it
//! on the person's row made it erasable by the person it constrains.

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
    /// restored purchase attributable to one identity.
    pub original_transaction_id: Option<String>,

    /// The individual purchase or renewal currently represented by the row.
    /// `None` is possible only for data written before migration 0033.
    pub transaction_id: Option<String>,
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
}

/// Counts the population in one pass. "Currently subscribed" is
/// `subscription_until > now()` — the same comparison `Entitlement::resolve`
/// makes on one row, written twice because a dashboard that disagreed with
/// the gate about who is paying would be worse than none. A sequential scan,
/// deliberately un-indexed: the cache runs it at most once a minute.
pub async fn census(pool: &PgPool) -> Result<Census, EntitlementError> {
    let row = sqlx::query!(
        r#"SELECT
             count(*) AS "users!",
             count(*) FILTER (
               WHERE subscription_tier = 'PLUS' AND subscription_until > now()
             ) AS "plus!"
           FROM users"#
    )
    .fetch_one(pool)
    .await?;

    Ok(Census {
        users: row.users,
        plus: row.plus,
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
            app_store_original_transaction_id AS original_transaction_id,
            app_store_transaction_id AS transaction_id
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

/// Whether Apple has revoked this individual transaction. New refunds are
/// exact `transactionId` matches; the lineage cutoff is read only for rows
/// written before migration 0033, which never retained the individual id. A
/// renewal signed after that cutoff stays usable, so no new refund is lineage-wide.
pub async fn transaction_was_revoked(
    pool: &PgPool,
    transaction_id: &str,
    original_transaction_id: &str,
    signed_at: DateTime<Utc>,
) -> Result<bool, EntitlementError> {
    let revoked = sqlx::query_scalar!(
        r#"SELECT (
             EXISTS (
               SELECT 1 FROM revoked_transactions
                WHERE transaction_id = $1
             )
             OR EXISTS (
               SELECT 1 FROM legacy_revoked_transaction_lineages
                WHERE original_transaction_id = $2
                  AND revoked_at >= $3
             )
           ) AS "revoked!""#,
        transaction_id,
        original_transaction_id,
        signed_at
    )
    .fetch_one(pool)
    .await?;

    Ok(revoked)
}

/// Writes one verified transaction onto the row, returning the row as stored.
/// The row moves together: a monthly crossgrade expires earlier than the year it
/// replaces, so keeping the later expiry billed monthly and entitled yearly.
/// Only forwards by `signedDate`, which orders `StoreKit`'s resubmits; a losing
/// submission is ordinary. `subscription_claimed_at` moves on every accept.
pub async fn apply_transaction(
    pool: &PgPool,
    user_id: UserId,
    transaction_id: &str,
    original_transaction_id: &str,
    tier: SubscriptionTier,
    until: DateTime<Utc>,
    signed_at: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    let row = sqlx::query_as!(
        EntitlementRow,
        r#"WITH moved AS (
             UPDATE users
                SET subscription_tier = $2,
                    subscription_until = $3,
                    app_store_transaction_id = $4,
                    app_store_original_transaction_id = $5,
                    subscription_signed_at = $6,
                    subscription_claimed_at = now(),
                    updated_at = now()
              WHERE id = $1
                AND (
                  subscription_signed_at IS NULL
                  OR subscription_signed_at < $6
                  OR (
                    subscription_signed_at = $6
                    AND app_store_transaction_id IS NULL
                  )
                )
                AND NOT EXISTS (
                  SELECT 1 FROM revoked_transactions
                   WHERE transaction_id = $4
                )
                AND NOT EXISTS (
                  SELECT 1 FROM legacy_revoked_transaction_lineages
                   WHERE original_transaction_id = $5
                     AND revoked_at >= $6
                )
             RETURNING subscription_tier, subscription_until,
                       app_store_original_transaction_id,
                       app_store_transaction_id
           )
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id,
             app_store_transaction_id AS transaction_id
           FROM moved
           UNION ALL
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id,
             app_store_transaction_id AS transaction_id
           FROM users
          WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM moved)"#,
        user_id.0,
        tier as SubscriptionTier,
        until,
        transaction_id,
        original_transaction_id,
        signed_at,
    )
    .fetch_optional(pool)
    .await?
    .ok_or(EntitlementError::Missing)?;

    Ok(row)
}

/// Records one exact refund and clears the grant only if that exact
/// transaction is still current — one database transaction, so a crash
/// cannot leave the tombstone without the clear. Matching on `transactionId`,
/// not the lineage, lets a late refund for an older period coexist with the
/// renewal still being paid; the null fallback covers pre-0033 rows.
pub async fn apply_revocation(
    pool: &PgPool,
    user_id: UserId,
    transaction_id: &str,
    original_transaction_id: &str,
    revoked_at: DateTime<Utc>,
    signed_at: DateTime<Utc>,
) -> Result<EntitlementRow, EntitlementError> {
    let mut tx = pool.begin().await?;

    sqlx::query!(
        "INSERT INTO revoked_transactions (
             transaction_id, original_transaction_id, revoked_at
         ) VALUES ($1, $2, $3)
         ON CONFLICT (transaction_id) DO NOTHING",
        transaction_id,
        original_transaction_id,
        revoked_at
    )
    .execute(&mut *tx)
    .await?;

    let row = sqlx::query_as!(
        EntitlementRow,
        r#"WITH moved AS (
             UPDATE users
                SET subscription_tier = NULL,
                    subscription_until = NULL,
                    app_store_transaction_id = $2,
                    app_store_original_transaction_id = $3,
                    subscription_signed_at = $4,
                    subscription_claimed_at = now(),
                    updated_at = now()
              WHERE id = $1
                AND (
                  app_store_transaction_id = $2
                  OR (
                    app_store_transaction_id IS NULL
                    AND app_store_original_transaction_id = $3
                  )
                )
                AND (subscription_signed_at IS NULL OR subscription_signed_at < $4)
             RETURNING subscription_tier, subscription_until,
                       app_store_original_transaction_id,
                       app_store_transaction_id
           )
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id,
             app_store_transaction_id AS transaction_id
           FROM moved
           UNION ALL
           SELECT
             subscription_tier AS "subscription_tier?: SubscriptionTier",
             subscription_until,
             app_store_original_transaction_id AS original_transaction_id,
             app_store_transaction_id AS transaction_id
           FROM users
          WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM moved)"#,
        user_id.0,
        transaction_id,
        original_transaction_id,
        signed_at
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(EntitlementError::Missing)?;

    tx.commit().await?;

    Ok(row)
}

/// Unbinds a transaction from the row holding it, so another identity may
/// claim it. Clears the binding and the grant together: half a release would
/// leave a row entitled by a transaction it no longer holds — the state
/// [`find_transaction_holder`] reads as a revocation. Whether the release is
/// allowed at all is `service::claim`'s decision.
pub async fn release_transaction(pool: &PgPool, user_id: UserId) -> Result<(), EntitlementError> {
    sqlx::query!(
        r#"UPDATE users
              SET subscription_tier = NULL,
                  subscription_until = NULL,
                  subscription_signed_at = NULL,
                  subscription_claimed_at = NULL,
                  app_store_transaction_id = NULL,
                  app_store_original_transaction_id = NULL,
                  updated_at = now()
            WHERE id = $1"#,
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(())
}
