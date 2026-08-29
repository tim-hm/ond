//! Account SQL — one column on `users`, the merge a returning sign-in performs,
//! and the erasure a departure does. Row existence is `crate::identity`'s
//! business, so nothing here inserts a user. This is the only repository that
//! *deletes* one, which is why merge and erasure both run in transactions with
//! the identity rows they act on locked.

use sqlx::{PgPool, Postgres, Transaction};

use super::authorization::{AuthorizationChallenge, AuthorizationNonceHash, AuthorizationPurpose};
use super::errors::AccountError;
use super::metrics::SignIn;
use crate::identity::{self, SessionCredential, UserId};

/// Stores one five-minute challenge for this caller and purpose, replacing an
/// older unconsumed ceremony for the same action.
pub async fn begin_authorization(
    pool: &PgPool,
    caller: UserId,
    purpose: AuthorizationPurpose,
    challenge: &AuthorizationChallenge,
) -> Result<(), AccountError> {
    sqlx::query!(
        "INSERT INTO apple_authorization_challenges (
             user_id, purpose, nonce_hash, expires_at
         ) VALUES ($1, $2::text::apple_authorization_purpose, $3, $4)
         ON CONFLICT (user_id, purpose) DO UPDATE SET
             nonce_hash = EXCLUDED.nonce_hash,
             expires_at = EXCLUDED.expires_at",
        caller.0,
        purpose.as_database(),
        challenge.hash().as_bytes(),
        challenge.expires_at()
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// The Apple account this identity is bound to, if any. Read before an
/// erasure: which credential the caller must present is a fact about their
/// row, not their request — a client that forgot it ever signed in still has
/// to prove the account is theirs. A missing row reads as unbound, not an
/// error, so a second deletion's honest answer — "it is gone" — needs no credential.
pub async fn apple_account_of(
    pool: &PgPool,
    caller: UserId,
) -> Result<Option<String>, AccountError> {
    Ok(
        sqlx::query_scalar!("SELECT apple_user_id FROM users WHERE id = $1", caller.0)
            .fetch_optional(pool)
            .await?
            .flatten(),
    )
}

/// Erases a user row, and with it everything the schema hangs off that row.
/// `bound_to` is the binding the caller actually proved, so a concurrent
/// `SignInWithApple` that rebinds the row makes this refuse. A row that is
/// already gone is not an error. What cascades, what survives, and what the
/// lock guards: docs/architecture.md, "Account lifecycle".
pub async fn delete_account(
    pool: &PgPool,
    caller: UserId,
    bound_to: Option<&str>,
    authorization_nonce: Option<&AuthorizationNonceHash>,
) -> Result<(), AccountError> {
    let mut tx = pool.begin().await?;

    let current = sqlx::query_scalar!(
        "SELECT apple_user_id FROM users WHERE id = $1 FOR UPDATE",
        caller.0
    )
    .fetch_optional(&mut *tx)
    .await?;

    if let Some(current) = current {
        if current.as_deref() != bound_to {
            return Err(AccountError::CredentialRequired);
        }

        if current.is_some() {
            let authorization_nonce = authorization_nonce.ok_or(AccountError::InvalidChallenge)?;
            consume_authorization(
                &mut tx,
                caller,
                AuthorizationPurpose::DeleteAccount,
                authorization_nonce,
            )
            .await?;
        }

        sqlx::query!("DELETE FROM users WHERE id = $1", caller.0)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;

    Ok(())
}

/// Binds `apple_user_id` to an identity and returns the id the device should
/// adopt. An identity already bound to an Apple account is never rebound, and
/// both [`claim`] and [`merge`] answer `AlreadyBound`. The three cases, the lock
/// order, and the accepted risk that an unbound id is claimable (TIM-99) are in
/// docs/architecture.md, "Account lifecycle".
pub async fn sign_in(
    pool: &PgPool,
    caller: UserId,
    apple_user_id: &str,
    authorization_nonce: &AuthorizationNonceHash,
) -> Result<(UserId, SignIn, SessionCredential), AccountError> {
    let mut tx = pool.begin().await?;

    consume_authorization(
        &mut tx,
        caller,
        AuthorizationPurpose::SignIn,
        authorization_nonce,
    )
    .await?;

    let holder = sqlx::query_scalar!(
        r#"SELECT id AS "id: UserId" FROM users WHERE apple_user_id = $1 FOR UPDATE"#,
        apple_user_id
    )
    .fetch_optional(&mut *tx)
    .await?;

    // The outcome travels out rather than being re-derived by the caller: from the
    // adopted id alone a merge is distinguishable and the other two are not, and
    // those two are "a new person" and "a returning one".
    let (adopted, outcome) = match holder {
        Some(held_by) if held_by == caller => (held_by, SignIn::Resumed),
        Some(held_by) => {
            merge(&mut tx, caller, held_by).await?;
            (held_by, SignIn::Merged)
        }
        None => {
            claim(&mut tx, caller, apple_user_id).await?;
            (caller, SignIn::Claimed)
        }
    };

    let credential = identity::start_session(&mut tx, adopted).await?;

    tx.commit().await?;

    Ok((adopted, outcome, credential))
}

/// Atomically spends a challenge only when all four facts match. Every failure
/// deliberately has the same answer, so the API does not reveal whether a
/// nonce existed for another caller or action.
async fn consume_authorization(
    tx: &mut Transaction<'_, Postgres>,
    caller: UserId,
    purpose: AuthorizationPurpose,
    nonce: &AuthorizationNonceHash,
) -> Result<(), AccountError> {
    let consumed = sqlx::query!(
        "DELETE FROM apple_authorization_challenges
          WHERE user_id = $1
            AND purpose = $2::text::apple_authorization_purpose
            AND nonce_hash = $3
            AND expires_at > now()",
        caller.0,
        purpose.as_database(),
        nonce.as_bytes()
    )
    .execute(&mut **tx)
    .await?;

    if consumed.rows_affected() != 1 {
        return Err(AccountError::InvalidChallenge);
    }

    Ok(())
}

/// Writes the binding onto the caller's own row, which nobody else holds.
/// Reads the current binding first rather than writing behind
/// `WHERE apple_user_id IS NULL`: the two ways that write could affect no rows
/// — a missing row and a row bound to somebody else — mean different things
/// to the caller, and `rows_affected` cannot tell them apart.
async fn claim(
    tx: &mut Transaction<'_, Postgres>,
    caller: UserId,
    apple_user_id: &str,
) -> Result<(), AccountError> {
    // The caller cannot be bound to *this* Apple account — the lookup that sent
    // us here found no row holding it — so any binding is another one.
    lock_unbound(tx, caller).await?;

    sqlx::query!(
        "UPDATE users SET apple_user_id = $2, updated_at = now() WHERE id = $1",
        caller.0,
        apple_user_id
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}

/// Locks the row and proves it unbound — the opening move `claim` and `merge`
/// share, so "never rebind a bound identity" has one owner. The `FOR UPDATE`
/// doubles as the existence check (no row is an identity that vanished after
/// the middleware created it), and each caller's own comment says why a
/// binding found here can only be another Apple account's.
async fn lock_unbound(tx: &mut Transaction<'_, Postgres>, id: UserId) -> Result<(), AccountError> {
    let binding = sqlx::query_scalar!(
        "SELECT apple_user_id FROM users WHERE id = $1 FOR UPDATE",
        id.0
    )
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(AccountError::Missing)?;

    if binding.is_some() {
        return Err(AccountError::AlreadyBound);
    }

    Ok(())
}

/// Folds the anonymous identity `from` into the signed-in identity `into`, then
/// deletes it. `into` survives with its own profile answers and the device adopts
/// its id; a `from` that is itself bound is refused as `AlreadyBound`. Which child
/// tables reparent, which are skipped, and why `from` is locked `FOR UPDATE` first
/// are in docs/architecture.md, "Account lifecycle".
async fn merge(
    tx: &mut Transaction<'_, Postgres>,
    from: UserId,
    into: UserId,
) -> Result<(), AccountError> {
    // `into` is bound by the time this runs, so `users.apple_user_id` being
    // `UNIQUE` makes any binding found here another Apple account's.
    lock_unbound(tx, from).await?;

    sqlx::query!(
        "UPDATE sessions AS moving
            SET user_id = $2
          WHERE moving.user_id = $1
            AND NOT EXISTS (
              SELECT 1 FROM sessions AS held
               WHERE held.user_id = $2
                 AND held.client_session_id = moving.client_session_id
            )",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "UPDATE bolt_scores AS moving
            SET user_id = $2
          WHERE moving.user_id = $1
            AND NOT EXISTS (
              SELECT 1 FROM bolt_scores AS held
               WHERE held.user_id = $2
                 AND held.client_score_id = moving.client_score_id
            )",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "UPDATE resting_rates AS moving
            SET user_id = $2
          WHERE moving.user_id = $1
            AND NOT EXISTS (
              SELECT 1 FROM resting_rates AS held
               WHERE held.user_id = $2
                 AND held.client_measurement_id = moving.client_measurement_id
            )",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "UPDATE user_techniques SET user_id = $2 WHERE user_id = $1",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "INSERT INTO assistant_usage (user_id, usage_date, calls)
         SELECT $2, usage_date, calls FROM assistant_usage WHERE user_id = $1
         ON CONFLICT (user_id, usage_date)
         DO UPDATE SET calls = assistant_usage.calls + EXCLUDED.calls",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    // Before the `DELETE`, in the same transaction: a merge that committed
    // without its tombstone leaves the retired id recreatable by
    // `identity::resolve`, which is the race `0019_merged_identities.sql`
    // exists to close.
    sqlx::query!(
        "INSERT INTO merged_identities (id, merged_into) VALUES ($1, $2)",
        from.0,
        into.0
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!("DELETE FROM users WHERE id = $1", from.0)
        .execute(&mut **tx)
        .await?;

    Ok(())
}
