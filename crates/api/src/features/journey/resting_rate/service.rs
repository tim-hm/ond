//! Business logic — validates a submitted resting rate and answers whether it
//! is a personal best.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use sqlx::PgPool;

use super::super::errors::JourneyError;
use super::super::wire::timestamp_from_proto;
use super::repository;
use super::types::RestingRateSnapshot;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire::{self, counted};

/// The slowest accepted rate, matching `resting_rates.breaths_per_minute`'s `CHECK`.
///
/// Below four breaths a minute a reading is a miscount or a held breath, so the
/// board cannot be won by not breathing. The floor sits well under the clinical
/// 12–20 range because practice moves people down through it.
const MIN_BREATHS_PER_MINUTE: u32 = 4;

/// The fastest rate this accepts. Above it the person was not at rest, and a
/// resting rate measured while they were not is not the measurement.
const MAX_BREATHS_PER_MINUTE: u32 = 60;

/// The rate at or below which the board stops distinguishing people.
///
/// Six breaths a minute is roughly the resonance frequency, where slow breathing
/// maximises respiratory sinus arrhythmia and baroreflex sensitivity (Russo et
/// al. 2017; Zaccaro et al. 2018). Without it the board rewards a breath hold.
pub const BOARD_FLOOR_BREATHS_PER_MINUTE: i32 = 6;

/// Records one resting rate and says where it leaves the person.
///
/// Idempotent on `(caller, client_measurement_id)`: a resend must cost nothing.
/// The server decides "personal best", and "best" means *lowest* here — see
/// [`RestingRateSnapshot`].
pub async fn record_resting_rate(
    pool: &PgPool,
    user_id: UserId,
    request: pb::RecordRestingRateRequest,
) -> Result<pb::RecordRestingRateResponse, JourneyError> {
    let rate = request.breaths_per_minute;
    if !(MIN_BREATHS_PER_MINUTE..=MAX_BREATHS_PER_MINUTE).contains(&rate) {
        return Err(JourneyError::Invalid(format!(
            "`breaths_per_minute` must be between {MIN_BREATHS_PER_MINUTE} \
             and {MAX_BREATHS_PER_MINUTE}"
        )));
    }
    let breaths_per_minute = i32::try_from(rate)
        .map_err(|_| JourneyError::Invalid("`breaths_per_minute` is out of range".to_owned()))?;

    let client_measurement_id =
        wire::uuid("client_measurement_id", &request.client_measurement_id)?;

    let measured_at = request
        .measured_at
        .map(|stamp| timestamp_from_proto(&stamp, "measured_at"))
        .transpose()?;

    // Read before the insert, because "is this their lowest" is a question about
    // the history that existed before it.
    let previous_lowest = lowest(pool, user_id).await?;
    repository::insert_resting_rate(
        pool,
        user_id,
        client_measurement_id,
        breaths_per_minute,
        measured_at,
    )
    .await?;

    Ok(pb::RecordRestingRateResponse {
        lowest_breaths_per_minute: previous_lowest.map_or(rate, |lowest| rate.min(lowest)),
        is_personal_best: previous_lowest.is_none_or(|lowest| rate < lowest),
    })
}

/// The caller's slowest measured rate, or `None` before they have measured one.
pub async fn lowest(pool: &PgPool, user_id: UserId) -> Result<Option<u32>, JourneyError> {
    Ok(repository::lowest_resting_rate(pool, user_id)
        .await?
        .map(|rate| counted("lowest_resting_rate", rate))
        .transpose()?)
}

/// The caller's whole resting-rate history folded to [`RestingRateSnapshot`], or
/// `None` before they have measured one. Read by
/// `sessions::service::practice_snapshot`: a sibling sub-feature reaches this
/// history through the service, never the repository.
pub async fn resting_rate_snapshot(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Option<RestingRateSnapshot>, JourneyError> {
    let row = repository::resting_rate_aggregate(pool, user_id).await?;
    let (Some(lowest), Some(latest)) = (row.lowest, row.latest) else {
        return Ok(None);
    };

    Ok(Some(RestingRateSnapshot {
        lowest: counted("lowest_resting_rate", lowest)?,
        latest: counted("latest_resting_rate", latest)?,
        count: counted("resting_rate_count", row.count)?,
    }))
}
