//! Identity SQL — whether a `users` row exists, and creating it if it does not.
//!
//! Outside `features/` because the row belongs to no feature. It is written on
//! the first RPC of any kind, whichever one that is, and `features::profile`
//! owns only the answer columns on it.

use sqlx::PgPool;

use super::UserId;

/// Whether we have seen this caller before.
///
/// Split out from the insert, and asked first, because the budget that rations
/// new identities has to be consulted *before* anything is written — a check
/// after the fact caps nothing, since the row it would have refused already
/// exists. This is what turns the write on the path of every identified request
/// into a primary-key lookup on the path of every *returning* one, which is the
/// overwhelming majority.
///
/// A concurrent pair of first sights can both read `false` and both spend from
/// the budget. That costs one unit of allowance, not a second row: [`create`]
/// still declines the conflict.
pub async fn is_known(pool: &PgPool, user_id: UserId) -> Result<bool, sqlx::Error> {
    let row = sqlx::query_scalar!("SELECT 1 FROM users WHERE id = $1", user_id.0)
        .fetch_optional(pool)
        .await?;

    Ok(row.is_some())
}

/// Records a caller we have not seen before.
///
/// `DO NOTHING` rather than `DO UPDATE`: every profile column has a default that
/// says "they have not answered", and an upsert that touched them would let a
/// stray RPC reset a profile back to empty. It also absorbs the race
/// [`is_known`] describes.
pub async fn create(pool: &PgPool, user_id: UserId) -> Result<(), sqlx::Error> {
    sqlx::query!(
        "INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING",
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(())
}
