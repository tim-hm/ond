//! Identity SQL — what the `users` row says about a caller, creating it if it
//! does not exist, and the credential rows that prove a signed-in one.
//!
//! Outside `features/` because the row belongs to no feature. It is written on
//! the first RPC of any kind, whichever one that is, and `features::profile`
//! owns only the answer columns on it.

use sqlx::PgPool;

use super::UserId;
use super::credential::{CredentialHash, SessionCredential, SessionError};

/// What the database says about a caller and the credential they presented.
///
/// The two travel together because one query answers both, and because the
/// decision `resolve` makes needs both at once: an unbound row is refused
/// nothing, and a bound one is refused everything without a live credential.
pub struct Standing {
    /// Whether the row carries an `apple_user_id`.
    pub bound: bool,
    /// Whether the presented credential matches a live session on this row.
    ///
    /// Always `false` when nothing was presented, which is what makes a bound
    /// row with no credential header indistinguishable from one with a wrong
    /// credential — the caller learns only that they may not proceed.
    pub credentialed: bool,
}

/// Reads the caller's standing, or `None` if we have never seen them.
///
/// One query rather than three, on the path of every identified request. The
/// existence check that used to live here is `Option`'s job now, the binding is
/// a column on the row already being located, and the credential is an `EXISTS`
/// against a primary-key lookup — so a signed-in caller costs the same round
/// trip an anonymous one always did.
///
/// `credential` is `None` when the request carried no credential header, and
/// binds SQL `NULL`: nothing equals `NULL`, so the `EXISTS` is false without a
/// second code path deciding so.
///
/// Asked before anything is written, because the budget that rations new
/// identities has to be consulted *before* the row it would have refused
/// exists. A concurrent pair of first sights can both read `None` and both spend
/// from that budget; that costs one unit of allowance, not a second row, since
/// [`create`] still declines the conflict.
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

    Ok(row.map(|row| Standing {
        bound: row.bound,
        credentialed: row.credentialed,
    }))
}

/// Records a caller we have not seen before.
///
/// `DO NOTHING` rather than `DO UPDATE`: every profile column has a default that
/// says "they have not answered", and an upsert that touched them would let a
/// stray RPC reset a profile back to empty. It also absorbs the race
/// [`standing`] describes.
pub async fn create(pool: &PgPool, user_id: UserId) -> Result<(), sqlx::Error> {
    sqlx::query!(
        "INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING",
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// Mints a credential for a caller who has just proved an Apple account, and
/// stores its hash.
///
/// Returns the secret, which is the only moment it exists anywhere but the
/// client's Keychain. Minting and storing are one function so that no caller can
/// hold a credential the database has not been told about — the failure worth
/// designing for is the other order, where a client is handed a secret that
/// proves nothing.
///
/// One row per sign-in rather than one per identity: a person signed in on a
/// phone and an iPad holds two credentials, and signing out of one must not
/// unseat the other.
pub async fn start_session(
    pool: &PgPool,
    user_id: UserId,
) -> Result<SessionCredential, SessionError> {
    let credential = SessionCredential::mint()?;

    sqlx::query!(
        "INSERT INTO user_sessions (token_hash, user_id) VALUES ($1, $2)",
        credential.hash().as_bytes(),
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(credential)
}

/// Revokes exactly the credential presented, and only if it belongs to the
/// caller.
///
/// Scoped to `user_id` as well as to the hash so that the statement cannot
/// revoke somebody else's credential even if one were somehow presented; the
/// hash alone is 256 bits of guessing, and the extra predicate is free on a
/// primary-key lookup.
///
/// Silent about whether anything was deleted. Sign-out is the client saying it
/// has finished with a credential, and a caller who has already discarded it —
/// or never had one, being anonymous — has nothing to be told.
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
