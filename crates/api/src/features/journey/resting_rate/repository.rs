//! Resting-rate SQL.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use super::super::errors::JourneyError;
use crate::identity::UserId;

/// Stores a measurement unless the caller has already sent that one.
///
/// `ON CONFLICT DO NOTHING` on `(user_id, client_measurement_id)`, the contract
/// every stream draining the client's one sync queue carries: a retry has to be
/// free, or a resend would quietly install a rate nobody measured twice.
pub async fn insert_resting_rate(
    pool: &PgPool,
    user_id: UserId,
    client_measurement_id: Uuid,
    breaths_per_minute: i32,
    measured_at: Option<DateTime<Utc>>,
) -> Result<(), JourneyError> {
    sqlx::query!(
        "INSERT INTO resting_rates (
             user_id, client_measurement_id, breaths_per_minute, measured_at
         )
         VALUES ($1, $2, $3, coalesce($4, now()))
         ON CONFLICT (user_id, client_measurement_id) DO NOTHING",
        user_id.0,
        client_measurement_id,
        breaths_per_minute,
        measured_at
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// The caller's slowest rate, or `None` before they have measured one.
///
/// `min` rather than `max`, which is the whole of what makes this measurement's
/// personal best read backwards from the pause's.
pub async fn lowest_resting_rate(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Option<i32>, JourneyError> {
    let lowest = sqlx::query_scalar!(
        "SELECT min(breaths_per_minute) FROM resting_rates WHERE user_id = $1",
        user_id.0
    )
    .fetch_one(pool)
    .await?;

    Ok(lowest)
}

/// The three folds `super::service::resting_rate_snapshot` serves. `lowest` and
/// `latest` are `None` together, exactly when `count` is zero.
pub struct RestingRateAggregateRow {
    pub lowest: Option<i32>,
    pub latest: Option<i32>,
    pub count: i64,
}

/// Lowest, latest and count in one statement, so the three figures were true
/// together — the same reason `bolt::repository::bolt_aggregate` is one
/// statement, and the same id tie-break making "latest" deterministic when two
/// measurements share a `measured_at`. Where the two part company is the
/// ordered `array_agg` below: a controlled pause is taken by hand and stays in
/// the dozens, and `bolt_aggregate` says so, while a client can measure a
/// resting rate every night.
///
/// "Latest" is a subquery rather than the tail of an ordered `array_agg`,
/// because the aggregate form sorted the whole of one person's history on every
/// call to take one row from it — on the request path the assistant fans out
/// hardest, and against a table a client taking a nightly measurement grows for
/// the life of the install. `resting_rates_user_measured_idx` orders by exactly
/// this tie-break, so what runs now is one descent and one row.
pub async fn resting_rate_aggregate(
    pool: &PgPool,
    user_id: UserId,
) -> Result<RestingRateAggregateRow, JourneyError> {
    let row = sqlx::query_as!(
        RestingRateAggregateRow,
        r#"SELECT min(breaths_per_minute) AS lowest,
                (SELECT latest.breaths_per_minute
                 FROM resting_rates latest
                 WHERE latest.user_id = $1
                 ORDER BY latest.measured_at DESC, latest.client_measurement_id DESC
                 LIMIT 1) AS latest,
                count(*) AS "count!"
         FROM resting_rates
         WHERE user_id = $1"#,
        user_id.0
    )
    .fetch_one(pool)
    .await?;

    Ok(row)
}
