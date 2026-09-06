//! Business logic — orders the reads and writes one RPC needs, and folds the
//! rows it gets back. Conversion is in `super::convert`, the clock checks in
//! `super::validation`, and every raw query in `super::repository`. Receives
//! explicit dependencies (`&PgPool`), never `Arc<AppState>`.

use std::collections::HashSet;

use sqlx::PgPool;

use super::super::bolt;
use super::super::errors::JourneyError;
use super::super::wire::validated_offset;
use super::convert::{session_from_proto, session_to_proto};
use super::repository::{self, StreakRow, TotalsRow};
use super::types::SessionCursor;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire::{self, counted};

/// How many sessions one call may carry.
///
/// A person breathing every waking hour for a month would not reach this, so it
/// bounds a client that has lost track of what it sent rather than a client
/// with a genuine backlog. The queue splits anything larger.
const MAX_SESSIONS_PER_BATCH: u32 = 200;

/// How much history one page carries when the caller does not say.
///
/// The journey screen's strip: the last few weeks at a glance. A restore asks
/// for more and pages, which is what the default stopped being able to express
/// once the strip's bound was also the whole of the restore path.
const DEFAULT_SESSION_PAGE: usize = 50;

/// The largest page this server will assemble.
///
/// Sized for the restore rather than the strip. A person with three years of
/// daily practice recovers in three round trips, and the ceiling is what stops
/// one request folding an unbounded history into a single response body.
const MAX_SESSION_PAGE: usize = 500;

/// Stores a batch of finished sessions and says how many were new. Idempotent
/// on `(caller, client_session_id)`, so a client may re-send anything it is
/// unsure about: `recorded` counts the rows really inserted and `already_known`
/// accounts for the rest. One impossible record fails the whole batch, because
/// recording the other ninety-nine would hide a client bug behind a gap.
pub async fn record_sessions(
    pool: &PgPool,
    user_id: UserId,
    submitted: Vec<pb::SessionRecord>,
) -> Result<pb::RecordSessionsResponse, JourneyError> {
    if submitted.is_empty() {
        return Err(JourneyError::Invalid("`sessions` is empty".to_owned()));
    }

    // Saturating rather than failing: a length past `u32::MAX` is past the batch
    // limit too, so it falls out of the same check with the same message.
    let submitted_count = u32::try_from(submitted.len()).unwrap_or(u32::MAX);
    if submitted_count > MAX_SESSIONS_PER_BATCH {
        return Err(JourneyError::Invalid(format!(
            "`sessions` carries more than {MAX_SESSIONS_PER_BATCH} records"
        )));
    }

    // Deduplicated before the insert rather than left to `ON CONFLICT`, so that
    // a batch repeating one id reports it as already known instead of as a row
    // the database quietly skipped.
    let mut seen = HashSet::with_capacity(submitted.len());
    let mut rows = Vec::with_capacity(submitted.len());
    for record in &submitted {
        let row = session_from_proto(record)?;
        if seen.insert(row.client_session_id) {
            rows.push(row);
        }
    }

    let inserted = repository::insert_sessions(pool, user_id, &rows).await?;
    let recorded: u32 = counted("recorded", inserted)?;

    Ok(pb::RecordSessionsResponse {
        recorded,
        already_known: submitted_count.saturating_sub(recorded),
    })
}

/// Forgets the sessions a person deleted on their device.
///
/// Ids the server does not hold are counted out rather than refused: the client
/// keeps a tombstone until this call succeeds, so it is entitled to send the
/// same id again and a second attempt must not fail the whole batch.
pub async fn delete_sessions(
    pool: &PgPool,
    user_id: UserId,
    submitted: Vec<String>,
) -> Result<pb::DeleteSessionsResponse, JourneyError> {
    if submitted.is_empty() {
        return Err(JourneyError::Invalid(
            "`client_session_ids` is empty".to_owned(),
        ));
    }

    if submitted.len() > MAX_SESSIONS_PER_BATCH as usize {
        return Err(JourneyError::Invalid(format!(
            "`client_session_ids` carries more than {MAX_SESSIONS_PER_BATCH} ids"
        )));
    }

    let mut ids = Vec::with_capacity(submitted.len());
    for raw in &submitted {
        ids.push(wire::uuid("client_session_ids entry", raw)?);
    }

    let removed = repository::delete_sessions(pool, user_id, &ids).await?;

    Ok(pb::DeleteSessionsResponse {
        deleted: counted("deleted", removed)?,
    })
}

/// The caller's totals, streaks, best pause, and one page of their history, for
/// two callers with opposite needs. The journey screen asks for the default page
/// and draws everything from the answer. A device restoring after a reinstall
/// asks for a large page with `sessions_only` and follows `next_page_token` to
/// the end — the only walk over the whole archive, and it wants no numbers.
pub async fn get_journey(
    pool: &PgPool,
    user_id: UserId,
    request: pb::GetJourneyRequest,
) -> Result<pb::GetJourneyResponse, JourneyError> {
    let offset = validated_offset(request.utc_offset_minutes)?;
    let limit = match request.limit {
        None => DEFAULT_SESSION_PAGE,
        // Refused rather than rounded up to one, the same rule every other
        // number in this file follows: a page of one would walk a whole history
        // one record at a time, which is not what anybody asking for zero meant.
        Some(0) => {
            return Err(JourneyError::Invalid(
                "`limit` must be at least 1".to_owned(),
            ));
        }
        // A value past `usize` is past the ceiling too, so both land on the cap.
        Some(asked) => {
            usize::try_from(asked).map_or(MAX_SESSION_PAGE, |asked| asked.min(MAX_SESSION_PAGE))
        }
    };
    let cursor = request
        .page_token
        .as_deref()
        .map(SessionCursor::decode)
        .transpose()?;

    // One row past the page, so whether another page exists is the database's
    // answer rather than an inference — and so a history that ends exactly on a
    // page boundary does not cost a restore an extra empty round trip.
    let overfetch = i64::try_from(limit).unwrap_or(i64::MAX).saturating_add(1);
    // Concurrent because none of these depends on another and the streak fold is
    // the slowest: serialising would put its latency in front of three cheap
    // queries on the screen a person opens to see their numbers.
    let (
        Aggregates {
            totals,
            streaks,
            best_bolt,
        },
        mut page,
    ) = tokio::try_join!(
        aggregates(pool, user_id, offset, !request.sessions_only),
        repository::recent_sessions(pool, user_id, overfetch, cursor),
    )?;

    let has_more = page.len() > limit;
    page.truncate(limit);
    let next_page_token = page
        .last()
        .filter(|_| has_more)
        .map(|row| SessionCursor::from(row).encode());

    Ok(pb::GetJourneyResponse {
        totals: Some(pb::JourneyTotals {
            sessions: counted("sessions", totals.sessions)?,
            breaths: counted("breaths", totals.breaths)?,
            minutes: counted("minutes", totals.duration_ms / 60_000)?,
        }),
        current_streak_days: counted("current_streak_days", streaks.current)?,
        best_streak_days: counted("best_streak_days", streaks.best)?,
        recent_sessions: page
            .into_iter()
            .map(session_to_proto)
            .collect::<Result<Vec<_>, JourneyError>>()?,
        best_bolt_seconds: best_bolt,
        next_page_token,
    })
}

/// The three whole-history numbers a `GetJourney` response carries beside the
/// page: totals, the streak fold, and the best pause.
#[derive(Default)]
struct Aggregates {
    totals: TotalsRow,
    streaks: StreakRow,
    best_bolt: Option<u32>,
}

/// Reads the [`Aggregates`] concurrently, or returns zeroes without touching
/// the database when the caller said it does not want them. These are the
/// heaviest per-person reads here: an unwindowed scan, a gaps-and-islands fold
/// and a whole-history maximum. A restore reads only the sessions and the token
/// off each page (`JourneyRepository.storedSessions`), so it skips all three.
async fn aggregates(
    pool: &PgPool,
    user_id: UserId,
    utc_offset_minutes: i32,
    wanted: bool,
) -> Result<Aggregates, JourneyError> {
    // `wanted` comes from the request's `sessions_only`, not from whether a page
    // token was presented. Inferring it would exempt the first page of every
    // restore — the one page a walk always has — and would leave a zeroed
    // response ambiguous between "asked not to compute" and "has no history".
    if !wanted {
        return Ok(Aggregates::default());
    }

    let (totals, streaks, best_bolt) = tokio::try_join!(
        repository::totals(pool, user_id),
        repository::streaks(pool, user_id, utc_offset_minutes),
        bolt::service::best_seconds(pool, user_id),
    )?;

    Ok(Aggregates {
        totals,
        streaks,
        best_bolt,
    })
}
