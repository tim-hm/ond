//! Assistant SQL — the daily model-call allowance, and nothing else.
//!
//! No prompt or reply is stored anywhere. What somebody typed in
//! their intent note already lives on `users`; a second copy inside a logged
//! prompt would be the same sentence in a table nobody remembers to think about.

use sqlx::PgPool;

use super::errors::AssistantError;
use crate::identity::UserId;

/// Claims one call against today's allowance, returning whether there was one
/// to claim. A single statement on purpose: read-then-write would let two
/// concurrent requests both take the last call — the `WHERE` on the conflict
/// branch makes the limit part of the update. Charged before the call: a
/// timed-out call still cost money, so a failing model must not retry freely.
pub async fn claim_daily_call(
    pool: &PgPool,
    user_id: UserId,
    limit: i32,
) -> Result<bool, AssistantError> {
    let claimed = sqlx::query_scalar!(
        "INSERT INTO assistant_usage (user_id, usage_date, calls)
         VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)
         ON CONFLICT (user_id, usage_date)
           DO UPDATE SET calls = assistant_usage.calls + 1
           WHERE assistant_usage.calls < $2
         RETURNING calls",
        user_id.0,
        limit
    )
    .fetch_optional(pool)
    .await?;

    Ok(claimed.is_some())
}
