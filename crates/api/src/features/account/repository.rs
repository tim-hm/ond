//! Account SQL — one column on `users`, the merge a returning sign-in performs,
//! and the erasure a departure does.
//!
//! The row's existence is `crate::identity`'s business, which is why nothing
//! here inserts a user. What it does do that no other repository does is *delete*
//! one — which is why the merge runs inside a single transaction, and why the
//! erasure below explains at length why it needs neither transaction nor lock.

use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use super::errors::AccountError;
use crate::identity::UserId;

/// The Apple account this identity is bound to, if it is bound to one.
///
/// Read before an erasure, because which credential the caller has to present is
/// a fact about their row rather than about their request — a client that has
/// forgotten it ever signed in still has to prove the account is theirs.
///
/// A missing row reads as unbound rather than as an error, which keeps
/// [`delete_account`]'s answer to a second deletion of the same identity honest:
/// "it is gone" needs no credential.
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
///
/// One `DELETE`, because the schema already says what erasure means. `sessions`
/// and `bolt_scores` (`0005_journey.sql`), `resting_rates`
/// (`0022_resting_rates.sql`), `assistant_usage`
/// (`0006_assistant_quota.sql`) and `user_sessions` (`0018_user_sessions.sql`)
/// are all `ON DELETE CASCADE` — which is how erasure revokes every credential
/// the identity ever minted without naming one — the profile answers are columns
/// on `users` itself (`0004_users_and_profiles.sql`), and the App
/// Store binding is two more columns — so it is released here exactly as [`merge`]
/// releases the identity it folds away, leaving the transaction free to entitle
/// whoever presents it next. What Apple *revoked* is not released with it:
/// `revoked_transactions` is filed against the purchase rather than the person.
///
/// The lock is not [`merge`]'s. That one exists to stop a concurrent write being
/// cascaded away *while the row survives*, a hazard erasure does not have —
/// nothing survives here, so a sync holding `FOR KEY SHARE` merely makes this
/// wait, and whatever it committed goes with the cascade. This lock guards the
/// *decision*: `service::delete_account` reads the binding, then verifies a
/// credential against Apple, which is a network round trip no transaction may be
/// held across. Between those two moments a concurrent `SignInWithApple` can
/// bind the row — so `bound_to` carries what was actually proved, and a binding
/// that has changed under the caller refuses rather than erasing an Apple
/// account nobody presented a credential for.
///
/// A row that is already gone is not an error, and is why this reads before it
/// writes rather than checking `rows_affected`: the middleware has just created
/// the row if it were missing, so the only way to find none is a second deletion
/// of the same identity, and "it is gone" is the honest answer to that.
///
/// What this cannot defend against is the request *after* it. `identity::resolve`
/// upserts a row for any well-formed id it holds no merge tombstone for, so a
/// client that goes on sending the erased one recreates it empty — which is why
/// `DeleteAccount` requires the
/// device to mint a fresh identity before it sends anything else, and why the
/// e2e suite pins that behaviour rather than leaving it as a remark.
pub async fn delete_account(
    pool: &PgPool,
    caller: UserId,
    bound_to: Option<&str>,
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

        sqlx::query!("DELETE FROM users WHERE id = $1", caller.0)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;

    Ok(())
}

/// Binds `apple_user_id` to an identity and returns the one the device should
/// adopt.
///
/// Three cases, decided by which row — if any — already holds the Apple account:
///
/// - **Nobody holds it.** The caller's row takes it, and the caller keeps its
///   own id. This is a first sign-in.
/// - **The caller holds it.** Nothing to do. A client that signs in again on the
///   same installation gets its own id back rather than an error.
/// - **Another row holds it.** That row is this person's real history, so the
///   caller's is folded into it by [`merge`] and the device adopts its id —
///   unless the caller is itself bound to some third Apple account, which is
///   refused.
///
/// The refusal in the last two cases is one rule, not two: an identity already
/// bound to an Apple account is never rebound, and both [`claim`] and [`merge`]
/// answer `AlreadyBound`. Which of them a caller reaches depends only on whether
/// anybody happens to hold the account being signed in to — invisible from the
/// device, and no basis for the difference between an error and a deletion.
///
/// One transaction over all three, with the holding row locked before anything
/// is read off it: two devices signing into one Apple account at the same moment
/// must not both decide they are the first, and `users.apple_user_id` being
/// `UNIQUE` turns the race that gets past the lock into a failed statement rather
/// than a second row.
///
/// ## Accepted risk: an unbound id is claimable by whoever presents it (TIM-99)
///
/// The first case asks for no proof beyond possession of the id, so somebody
/// who obtains an id that has never signed in can bind it to *their own* Apple
/// account — taking the practice history with it, and leaving the victim's
/// device holding an id it can no longer prove. This is indistinguishable, from
/// here, from the ordinary case this function exists to serve: a person signing
/// in for the first time on the device they have been practising on. Both are
/// an unbound row meeting an Apple account for the first time.
///
/// Accepted rather than closed, because the exposure is narrow on every axis.
/// An unbound row carries no money, no name and no email — sign-in is required
/// to subscribe — so what is stealable is a breathing log, unpleasant rather
/// than lucrative. And obtaining the full id requires the device or its backup:
/// the Settings row and the support-email flow carry only the twelve-hex-digit
/// `SupportReference`, which names a row without being the claim to it. A
/// mechanism that told the two cases apart would need the device to prove it
/// has been practising under the id, which is device attestation — out of all
/// proportion to what it protects, and revisitable if an unbound row ever
/// carries more. `web/privacy.html` claims protection only for signed-in
/// identities, which matches what this gives.
pub async fn bind_apple_account(
    pool: &PgPool,
    caller: UserId,
    apple_user_id: &str,
) -> Result<Uuid, AccountError> {
    let mut tx = pool.begin().await?;

    let holder = sqlx::query_scalar!(
        "SELECT id FROM users WHERE apple_user_id = $1 FOR UPDATE",
        apple_user_id
    )
    .fetch_optional(&mut *tx)
    .await?;

    let adopted = match holder {
        Some(held_by) if held_by == caller.0 => held_by,
        Some(held_by) => {
            merge(&mut tx, caller, held_by).await?;
            held_by
        }
        None => {
            claim(&mut tx, caller, apple_user_id).await?;
            caller.0
        }
    };

    tx.commit().await?;

    Ok(adopted)
}

/// Writes the binding onto the caller's own row, which nobody else holds.
///
/// Reads the row's current binding first rather than writing behind a
/// `WHERE apple_user_id IS NULL`, because the two ways that write could affect no
/// rows — a missing row and a row bound to somebody else — mean entirely
/// different things to the caller and `rows_affected` cannot tell them apart.
async fn claim(
    tx: &mut Transaction<'_, Postgres>,
    caller: UserId,
    apple_user_id: &str,
) -> Result<(), AccountError> {
    // The caller cannot be bound to *this* Apple account — the lookup that sent
    // us here found no row holding it — so any binding is another one.
    lock_unbound(tx, caller.0).await?;

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
/// share, so "never rebind a bound identity" has one owner rather than two
/// free to drift. The `FOR UPDATE` doubles as the existence check (no row to
/// lock is an identity that vanished between the middleware creating it and
/// this write), and each caller's own comment says why a binding found here
/// can only be another Apple account's.
async fn lock_unbound(tx: &mut Transaction<'_, Postgres>, id: Uuid) -> Result<(), AccountError> {
    let binding = sqlx::query_scalar!(
        "SELECT apple_user_id FROM users WHERE id = $1 FOR UPDATE",
        id
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
/// deletes it.
///
/// The device arrives carrying an id it minted on first launch and is signing in
/// to an Apple account that already has a row. Both may have history. The rule is
/// **reparent then delete**: `into`'s row survives with its own profile answers,
/// `from`'s children move onto it, and `from` goes. The device adopts `into`'s
/// id. The alternative — keeping `from` and moving the binding — would throw away
/// whichever history was older, which is the thing signing in exists to recover.
///
/// `from` must be anonymous, and the lock below is where that is checked. A row
/// carrying an `apple_user_id` of its own belongs to somebody who proved a
/// *different* Apple account, and folding it away would destroy the only record
/// that that account has a history — so it is refused as `AlreadyBound`, the same
/// answer [`claim`] gives the same person arriving by the other branch.
/// Possession of an anonymous id is the whole of the claim to it (`identity.rs`
/// says so), and that is not a credential this may weigh against a signed-in one.
///
/// Three sub-rules, each following from the schema rather than from taste:
///
/// - **`sessions`, `bolt_scores` and `resting_rates`** reparent, skipping a row
///   `into` already has. All three are keyed `(user_id, client_<thing>_id)` over
///   an id the *client* minted, so a key held on both sides is one record that
///   reached the server twice — never two things that happened. Written as a
///   `NOT EXISTS` guard
///   because `ON CONFLICT` belongs to `INSERT` and this is an `UPDATE`; the rows
///   it skips are left on `from` and go with the `ON DELETE CASCADE` below, which
///   is the same outcome by a shorter route than deleting them here.
/// - **`user_techniques`** reparent outright, with no guard. Their ids are
///   server-minted rather than client-minted, so two rows can never be one
///   record that arrived twice — and an exercise somebody wrote is the one thing
///   here that exists nowhere else, so there is nothing to reconstruct if it
///   goes. This can leave `into` holding more than `MAX_TECHNIQUES`, which is
///   deliberate: that ceiling gates composing another, and enforcing it here
///   would mean deleting somebody's work to make a number true.
/// - **`assistant_usage`** sums on a shared date. It is a spend limit, counted
///   per person per UTC day, so keeping `into`'s count would let signing in
///   launder whatever `from` had already spent — the same fan-out
///   `entitlement::service`'s `TRANSFER_COOLDOWN` exists to stop, reached by
///   another door.
/// - **Entitlements are not copied.** They are columns on `users` rather than a
///   child table, so deleting `from` releases its
///   `app_store_original_transaction_id` outright, and the client resubmits its
///   `StoreKit` transaction on every launch — `entitlement::service::claim` then
///   grants it to `into` against no holder at all. Copying them would mean
///   reasoning about `users_app_store_original_transaction_id_key` and the
///   transfer cooldown for an outcome the next launch produces by itself.
///
/// Every statement is in the caller's transaction. Half a merge is a person whose
/// sessions moved and whose breath-test history did not, with nothing left to
/// tell anyone it happened.
///
/// ## Why `from` is locked first
///
/// The lock is not tidiness, and its position above the reparents is the whole of
/// what it does. A sync landing on `from` at the same moment — the same device,
/// which has not been told its id is about to change — inserts a child row, and
/// that insert takes `FOR KEY SHARE` on `from`'s `users` row for the life of its
/// transaction. Nothing in the reparents conflicts with that lock, so without the
/// `FOR UPDATE` below the sequence is: the reparent runs against a snapshot taken
/// before the insert committed and does not see it, the insert commits, and the
/// `DELETE` then destroys it through `ON DELETE CASCADE`. Silent, and precisely
/// the history this function exists to preserve.
///
/// `FOR UPDATE` conflicts with `FOR KEY SHARE`, so taking it here makes the merge
/// wait for an in-flight write instead of stepping over it — and because each
/// statement takes its own snapshot under READ COMMITTED, the reparents that
/// follow the lock see everything it waited for. A write that starts *after* the
/// lock is held blocks, and then fails its foreign key once `from` is gone rather
/// than being cascaded away; the client resends under the id it has by then
/// adopted — or, before the handoff lands, is refused by the tombstone below
/// rather than recreated as an orphan. Either way the outcome loses nothing.
///
/// It doubles as the existence check the `DELETE` would otherwise need — no row to
/// lock is a caller whose identity vanished between the middleware creating it and
/// this write — and it reads the binding the anonymity check turns on, so proving
/// `from` anonymous costs no statement of its own.
async fn merge(
    tx: &mut Transaction<'_, Postgres>,
    from: UserId,
    into: Uuid,
) -> Result<(), AccountError> {
    // `into` holds the Apple account being signed in to and is a different row,
    // so `users.apple_user_id` being `UNIQUE` makes any binding here another one.
    lock_unbound(tx, from.0).await?;

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
        into
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
        into
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
        into
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "UPDATE user_techniques SET user_id = $2 WHERE user_id = $1",
        from.0,
        into
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "INSERT INTO assistant_usage (user_id, usage_date, calls)
         SELECT $2, usage_date, calls FROM assistant_usage WHERE user_id = $1
         ON CONFLICT (user_id, usage_date)
         DO UPDATE SET calls = assistant_usage.calls + EXCLUDED.calls",
        from.0,
        into
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
        into
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!("DELETE FROM users WHERE id = $1", from.0)
        .execute(&mut **tx)
        .await?;

    Ok(())
}
