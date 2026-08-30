//! Business logic — validates a submitted measurement and answers whether it is
//! a personal best.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use sqlx::PgPool;

use super::super::errors::JourneyError;
use super::super::wire::timestamp_from_proto;
use super::repository;
use super::types::BoltSnapshot;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire::{self, counted};

/// Matches the `CHECK` on `bolt_scores.seconds`.
const MAX_BOLT_SECONDS: u32 = 600;

/// The pause at or above which the board stops distinguishing people.
///
/// Forty seconds is the method's own target: above it a longer pause is not a
/// calmer person. Without a ceiling the board rewards a maximal hold, which
/// `BoltTestView` tells people not to attempt. The history keeps the full score.
pub const BOARD_CEILING_SECONDS: i32 = 40;

/// Records one controlled pause and says where it leaves the person.
///
/// Idempotent on `(caller, client_score_id)`: a resend must be free, and a
/// duplicate would otherwise hide behind `max(seconds)` on every board. The
/// server decides "personal best" because an offline device lacks the history.
pub async fn record_bolt_score(
    pool: &PgPool,
    user_id: UserId,
    request: pb::RecordBoltScoreRequest,
) -> Result<pb::RecordBoltScoreResponse, JourneyError> {
    if request.seconds == 0 || request.seconds > MAX_BOLT_SECONDS {
        return Err(JourneyError::Invalid(format!(
            "`seconds` must be between 1 and {MAX_BOLT_SECONDS}"
        )));
    }
    let seconds = i32::try_from(request.seconds)
        .map_err(|_| JourneyError::Invalid("`seconds` is out of range".to_owned()))?;

    let client_score_id = wire::uuid("client_score_id", &request.client_score_id)?;

    let measured_at = request
        .measured_at
        .map(|stamp| timestamp_from_proto(&stamp, "measured_at"))
        .transpose()?;

    // Read before the insert, because "is this a personal best" is a question
    // about the history that existed before it — asking afterwards would always
    // answer yes.
    let previous_best = best_seconds(pool, user_id).await?;
    repository::insert_bolt_score(pool, user_id, client_score_id, seconds, measured_at).await?;

    Ok(pb::RecordBoltScoreResponse {
        best_seconds: request.seconds.max(previous_best.unwrap_or(0)),
        is_personal_best: previous_best.is_none_or(|best| request.seconds > best),
    })
}

/// The caller's best pause, or `None` before they have taken one.
///
/// Read by `sessions::service::get_journey` as well as by the RPC above, so the
/// journey screen needs no second round trip. Narrowing onto the wire's unsigned
/// field happens once, here.
pub async fn best_seconds(pool: &PgPool, user_id: UserId) -> Result<Option<u32>, JourneyError> {
    Ok(repository::best_bolt_score(pool, user_id)
        .await?
        .map(|seconds| counted("best_bolt_seconds", seconds))
        .transpose()?)
}

/// The caller's whole BOLT history folded to [`BoltSnapshot`], or `None` before
/// they have taken the test. Read by `sessions::service::practice_snapshot`: a
/// sibling sub-feature reaches this history through the service, never the
/// repository.
pub async fn bolt_snapshot(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Option<BoltSnapshot>, JourneyError> {
    let row = repository::bolt_aggregate(pool, user_id).await?;
    let (Some(best), Some(latest)) = (row.best, row.latest) else {
        return Ok(None);
    };

    Ok(Some(BoltSnapshot {
        best: counted("best_bolt_seconds", best)?,
        latest: counted("latest_bolt_seconds", latest)?,
        count: counted("bolt_count", row.count)?,
    }))
}
