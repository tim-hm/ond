//! BOLT-score SQL.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use super::super::errors::JourneyError;
use crate::identity::UserId;

/// Stores a score unless the caller has already sent that one.
///
/// `ON CONFLICT DO NOTHING` on `(user_id, client_score_id)`, matching
/// `sessions::repository::insert_sessions`: both drain through one client queue,
/// so a retry must be free. `UserId` is a distinct type so a swap cannot compile.
pub async fn insert_bolt_score(
    pool: &PgPool,
    user_id: UserId,
    client_score_id: Uuid,
    seconds: i32,
    measured_at: Option<DateTime<Utc>>,
) -> Result<(), JourneyError> {
    sqlx::query!(
        "INSERT INTO bolt_scores (user_id, client_score_id, seconds, measured_at)
         VALUES ($1, $2, $3, coalesce($4, now()))
         ON CONFLICT (user_id, client_score_id) DO NOTHING",
        user_id.0,
        client_score_id,
        seconds,
        measured_at
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// The caller's best score, or `None` before they have taken the test.
pub async fn best_bolt_score(pool: &PgPool, user_id: UserId) -> Result<Option<i32>, JourneyError> {
    let best = sqlx::query_scalar!(
        "SELECT max(seconds) FROM bolt_scores WHERE user_id = $1",
        user_id.0
    )
    .fetch_one(pool)
    .await?;

    Ok(best)
}
