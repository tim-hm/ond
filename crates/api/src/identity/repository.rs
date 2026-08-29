//! Identity SQL — what the `users` row says about a caller, creating it if it
//! does not exist, and the credential rows that prove a signed-in one. Outside
//! `features/` because the row belongs to no feature: it is written on the
//! first RPC of any kind, and `features::profile` owns only the answer columns.

use sqlx::{PgPool, Postgres, Transaction};

use super::UserId;
use super::credential::{CredentialHash, SessionCredential, SessionError};

/// What the database says about a caller and the credential they presented.
///
/// The two travel together because one query answers both, and because the
/// decision `resolve` makes needs both at once: an unbound row is refused
/// nothing, and a bound one is refused everything without a live credential.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Standing {
    /// The row carries no Apple binding and needs no session credential.
    Anonymous,
    /// The row is Apple-bound and the presented credential proves it.
    BoundCredentialed,
    /// The row is Apple-bound but the request did not prove it.
    BoundUncredentialed,
}

/// Reads the caller's standing, or `None` if we have never seen them. A `None`
/// credential binds SQL `NULL` — nothing equals `NULL`, so the `EXISTS` is
/// false with no second code path deciding so. A concurrent pair of first
/// sights can both read `None` and both spend the new-identity budget; that
/// costs one unit of allowance, not a second row — [`create`] declines the conflict.
pub async fn standing(
    pool: &PgPool,
    user_id: UserId,
    credential: Option<&CredentialHash>,
) -> Result<Option<Standing>, sqlx::Error> {
    let row = sqlx::query!(
        r#"SELECT
             (users.apple_user_id IS NOT NULL) AS "bound!",
             EXISTS (
               SELECT 1 FROM user_sessions
                WHERE user_sessions.user_id = users.id
                  AND user_sessions.token_hash = $2
             ) AS "credentialed!"
           FROM users
          WHERE users.id = $1"#,
        user_id.0,
        credential.map(CredentialHash::as_bytes)
    )
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|row| match (row.bound, row.credentialed) {
        (false, _) => Standing::Anonymous,
        (true, true) => Standing::BoundCredentialed,
        (true, false) => Standing::BoundUncredentialed,
    }))
}

/// Whether this id names an identity a sign-in merge folded away. Asked only
/// on the branch that would otherwise recreate the row, so ordinary requests
/// never run it. A dead id is refused before the new-identity budget is spent:
/// a watch racing a sign-in is honest traffic and should not drain the
/// address's allowance for fresh installs.
pub async fn merged_away(pool: &PgPool, user_id: UserId) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar!(
        r#"SELECT EXISTS (
             SELECT 1 FROM merged_identities WHERE id = $1
           ) AS "merged!""#,
        user_id.0
    )
    .fetch_one(pool)
    .await
}

/// Records a caller we have not seen before, reporting whether a row was
/// written. `DO NOTHING` rather than `DO UPDATE`: every profile column has a
/// default meaning "not answered", and an upsert would let a stray RPC reset a
/// profile back to empty. It also absorbs [`standing`]'s race, which is why
/// the return value exists — only the row count can say "was this a new person".
pub async fn create(pool: &PgPool, user_id: UserId) -> Result<Created, sqlx::Error> {
    let result = sqlx::query!(
        "INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING",
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(if result.rows_affected() == 0 {
        Created::AlreadyExisted
    } else {
        Created::Row
    })
}

/// What [`create`] did, for a caller that wants to count first sightings.
///
/// A named pair rather than a `bool`, because `false` at a call site would read
/// as failure when it means the opposite: the row was already there.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Created {
    /// A row was inserted: this identity had never been seen.
    Row,
    /// The row already existed, so nothing was written.
    AlreadyExisted,
}

/// Mints a credential for a caller who has just proved an Apple account, and
/// stores its hash. Minting and storing are one function so no caller can hold
/// a credential the database has not been told about — a client handed a
/// secret that proves nothing is the failure worth designing for. One row per
/// sign-in: a phone and an iPad hold two, and signing out of one must not unseat the other.
pub async fn start_session(
    tx: &mut Transaction<'_, Postgres>,
    user_id: UserId,
) -> Result<SessionCredential, SessionError> {
    let credential = SessionCredential::mint()?;

    sqlx::query!(
        "INSERT INTO user_sessions (token_hash, user_id) VALUES ($1, $2)",
        credential.hash().as_bytes(),
        user_id.0
    )
    .execute(&mut **tx)
    .await?;

    Ok(credential)
}

/// Revokes exactly the credential presented, and only if it belongs to the
/// caller: scoped to `user_id` as well as the hash so the statement cannot
/// revoke somebody else's credential, and the extra predicate is free on a
/// primary-key lookup. Silent about whether anything was deleted — a caller
/// who already discarded it, or never had one, has nothing to be told.
pub async fn end_session(
    pool: &PgPool,
    user_id: UserId,
    credential: &CredentialHash,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        "DELETE FROM user_sessions WHERE user_id = $1 AND token_hash = $2",
        user_id.0,
        credential.as_bytes()
    )
    .execute(pool)
    .await?;

    Ok(())
}
