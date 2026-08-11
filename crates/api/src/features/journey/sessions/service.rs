//! Business logic — validates what a client claims it did, and converts both
//! ways across the proto boundary.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use std::collections::HashSet;

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use super::super::bolt;
use super::super::bolt::types::BoltSnapshot;
use super::super::errors::JourneyError;
use super::super::resting_rate;
use super::super::resting_rate::types::RestingRateSnapshot;
use super::super::wire::{timestamp_from_proto, validated_offset};
use super::repository::{self, SessionRow, StreakRow, TechniquePracticeRow, TotalsRow};
use super::types::{
    LifetimeTotals, MAX_SNAPSHOT_TECHNIQUES, PRACTICE_WINDOW_DAYS, PracticeSnapshot, SessionCursor,
    StreakSummary, TechniquePractice,
};
use crate::features::technique::types::MAX_SLUG_CHARS;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire::{counted, timestamp_to_proto};

/// How many sessions one call may carry.
///
/// A person breathing every waking hour for a month would not reach this, so it
/// bounds a client that has lost track of what it sent rather than a client
/// with a genuine backlog. The queue splits anything larger.
const MAX_SESSIONS_PER_BATCH: u32 = 200;

/// Twelve hours. Longer than any session the app can produce and short enough
/// that a stuck timer arrives as a rejection rather than as a person's totals.
const MAX_SESSION_DURATION_MS: u32 = 12 * 60 * 60 * 1000;

const MAX_CYCLES_PER_SESSION: u32 = 10_000;
const MAX_BREATHS_PER_SESSION: u32 = 100_000;

/// 2025-01-01T00:00:00Z, as an epoch second.
///
/// No session predates the first build of the app, and a row dated earlier is a
/// broken clock rather than a memory. Rejected rather than clamped: a silently
/// moved date would land in somebody's streak.
///
/// A timestamp rather than an RFC 3339 string so the check is a comparison
/// rather than a parse repeated for all two hundred records of a batch — and so
/// there is no unparseable case to invent a fallback for.
const EARLIEST_SESSION_TIMESTAMP: i64 = 1_735_689_600;

/// How far ahead of the server's clock a session may claim to have started.
///
/// Generous enough to absorb a device whose clock is a few hours out, tight
/// enough that a session dated next year cannot hold a streak open forever.
const MAX_CLOCK_SKEW_HOURS: i64 = 24;

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

/// Stores a batch of finished sessions and says how many were new.
///
/// Idempotent on `(caller, client_session_id)`, which is what lets a client
/// re-send anything it is unsure about: `recorded` counts rows the database
/// really inserted and `already_known` accounts for the rest, so a retry is the
/// ordinary path rather than an error.
///
/// One impossible record fails the whole batch. A client that sent a session the
/// app cannot have produced has a bug, and quietly recording the other
/// ninety-nine would hide it behind a gap nobody can find.
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
        ids.push(Uuid::parse_str(raw).map_err(|_| {
            JourneyError::Invalid(format!("`client_session_ids` entry `{raw}` is not a UUID"))
        })?);
    }

    let removed = repository::delete_sessions(pool, user_id, &ids).await?;

    Ok(pb::DeleteSessionsResponse {
        deleted: counted("deleted", removed)?,
    })
}

/// The caller's totals, streaks, best pause, and one page of their history.
///
/// Serves two callers with opposite needs from one RPC. The journey screen asks
/// for the default page and draws everything it needs from the answer. A device
/// restoring after a reinstall — where the Keychain identity survived and the
/// sessions file did not — asks for a large page with `sessions_only`, and
/// follows `next_page_token` until none comes back; that walk is the only
/// mechanism that returns the archive rather than the strip, and it wants none
/// of the numbers above it — see [`aggregates`].
///
/// The reads are concurrent because none depends on any other and the streak
/// fold is the slowest of them, so serialising would put its latency in front of
/// three cheap queries on the screen a person opens to see their numbers.
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

/// Reads the [`Aggregates`], concurrently — or returns zeroes without touching
/// the database when the caller said it does not want them.
///
/// The three are the heaviest per-person reads in the feature: an unwindowed
/// scan, a gaps-and-islands fold, and a whole-history maximum. The journey
/// screen asks for a page and draws all three; the reinstall restore walks up to
/// forty pages and reads only the sessions and the token off each
/// (`JourneyRepository.storedSessions` in `OndKit`), so computing them per page
/// had the people with the most rows paying four times per page for one page's
/// worth of useful work.
///
/// `wanted` comes from the request's `sessions_only` rather than from whether a
/// page token was presented. Inferring it would have exempted the first page of
/// every restore — the one page a walk always has — and would have made a zeroed
/// response ambiguous between "asked not to compute" and "has no history".
async fn aggregates(
    pool: &PgPool,
    user_id: UserId,
    utc_offset_minutes: i32,
    wanted: bool,
) -> Result<Aggregates, JourneyError> {
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

/// The caller's recent practice, folded down to the aggregate the assistant
/// reads.
///
/// Deliberately honest raw aggregates: the slugs are client-supplied free text,
/// and nothing here checks them against the catalogue — the consumer holds the
/// catalogue and decides what an unresolvable slug becomes. The reads are
/// concurrent for the same reason `get_journey`'s are: none depends on another,
/// and this sits on the assistant's request path.
///
/// Most of it is a thirty-day window, and three figures deliberately are not.
/// Lifetime totals and the hours since the last session are what somebody means
/// by "how am I doing" and neither fits inside a month.
///
/// `utc_offset_minutes` is `None` for a caller that sent none, and the streak is
/// then absent rather than computed at UTC — see
/// [`StreakSummary`](super::types::StreakSummary). Everything else here is
/// offset-free, so a caller without one loses only the streak. An offset that is
/// *present and impossible* is refused rather than ignored: that is a client
/// bug, and dropping the streak for it would hide the bug behind a coach that
/// has simply stopped mentioning one.
pub async fn practice_snapshot(
    pool: &PgPool,
    user_id: UserId,
    utc_offset_minutes: Option<i32>,
) -> Result<PracticeSnapshot, JourneyError> {
    let (practice, active_days, bolt, resting_rate, totals, last_session_at) = tokio::try_join!(
        repository::recent_practice(pool, user_id),
        repository::active_days(pool, user_id),
        bolt::service::bolt_snapshot(pool, user_id),
        resting_rate::service::resting_rate_snapshot(pool, user_id),
        repository::totals(pool, user_id),
        repository::last_session_at(pool, user_id),
    )?;

    // Sequenced after the fan-out rather than joined into it, because it is the
    // one read that may not happen at all.
    let streak = match utc_offset_minutes {
        Some(minutes) => {
            Some(repository::streaks(pool, user_id, validated_offset(minutes)?).await?)
        }
        None => None,
    };

    assemble_snapshot(SnapshotParts {
        practice,
        active_days,
        bolt,
        resting_rate,
        totals,
        last_session_at,
        streak,
    })
}

/// Everything one snapshot is folded from, so the assembly takes one parameter
/// instead of seven positional ones nobody could read at a call site.
struct SnapshotParts {
    practice: Vec<TechniquePracticeRow>,
    active_days: i64,
    bolt: Option<BoltSnapshot>,
    resting_rate: Option<RestingRateSnapshot>,
    totals: TotalsRow,
    last_session_at: Option<DateTime<Utc>>,
    streak: Option<StreakRow>,
}

/// Folds the grouped rows into the snapshot: totals over every group, names
/// for only the busiest [`MAX_SNAPSHOT_TECHNIQUES`].
///
/// The totals sum the raw milliseconds before dividing, so a hundred short
/// sessions do not each lose their remainder — which is why the total minutes
/// can exceed the sum of the per-technique ones.
fn assemble_snapshot(parts: SnapshotParts) -> Result<PracticeSnapshot, JourneyError> {
    let SnapshotParts {
        practice,
        active_days,
        bolt,
        resting_rate,
        totals,
        last_session_at,
        streak,
    } = parts;

    let total_sessions: i64 = practice.iter().map(|row| row.sessions).sum();
    let total_duration_ms: i64 = practice.iter().map(|row| row.duration_ms).sum();

    let by_technique = practice
        .into_iter()
        .take(MAX_SNAPSHOT_TECHNIQUES)
        .map(|row| {
            Ok(TechniquePractice {
                technique_slug: row.technique_slug,
                sessions: counted("technique_sessions", row.sessions)?,
                minutes: counted("technique_minutes", row.duration_ms / 60_000)?,
            })
        })
        .collect::<Result<Vec<_>, JourneyError>>()?;

    // Absent rather than zeroed for somebody who has never practised: a lifetime
    // of nothing is what the "no practice recorded yet" line already says, and a
    // second line saying zero would say it twice.
    let lifetime = (totals.sessions > 0).then(|| {
        Ok::<_, JourneyError>(LifetimeTotals {
            sessions: counted("lifetime_sessions", totals.sessions)?,
            minutes: counted("lifetime_minutes", totals.duration_ms / 60_000)?,
        })
    });

    Ok(PracticeSnapshot {
        window_days: u32::from(PRACTICE_WINDOW_DAYS),
        sessions: counted("snapshot_sessions", total_sessions)?,
        minutes: counted("snapshot_minutes", total_duration_ms / 60_000)?,
        active_days: counted("active_days", active_days)?,
        by_technique,
        bolt,
        resting_rate,
        lifetime: lifetime.transpose()?,
        hours_since_last: last_session_at.map(hours_since),
        // A streak of zero is somebody who practised but not lately, which is a
        // true thing worth saying — so unlike the totals this is kept as it
        // comes, and only an absent offset makes it absent.
        streak: streak.map(|row| StreakSummary {
            current: row.current.max(0).unsigned_abs(),
            best: row.best.max(0).unsigned_abs(),
        }),
    })
}

/// Whole hours from an instant to now, floored, and zero for anything in the
/// future — a clock skewed forward on a client is not a session that has not
/// happened yet.
fn hours_since(started_at: DateTime<Utc>) -> u32 {
    let hours = (Utc::now() - started_at).num_hours();
    u32::try_from(hours.max(0)).unwrap_or(u32::MAX)
}

/// Narrows one submitted session to something the database accepts.
///
/// Every rejection is a value the wire format admits and no session can produce.
/// The whole batch fails rather than the offending record being dropped: a
/// client that sent one impossible session has a bug, and quietly recording the
/// other ninety-nine would hide it while leaving a gap nobody can find.
fn session_from_proto(record: &pb::SessionRecord) -> Result<SessionRow, JourneyError> {
    let client_session_id = Uuid::parse_str(&record.client_session_id).map_err(|_| {
        JourneyError::Invalid(format!(
            "`client_session_id` `{}` is not a UUID",
            record.client_session_id
        ))
    })?;

    let technique_slug = record.technique_slug.trim().to_owned();
    if technique_slug.is_empty() || technique_slug.chars().count() > MAX_SLUG_CHARS {
        return Err(JourneyError::Invalid(format!(
            "`technique_slug` must be between 1 and {MAX_SLUG_CHARS} characters"
        )));
    }

    let started_at = record
        .started_at
        .as_ref()
        .ok_or_else(|| JourneyError::Invalid("`started_at` is required".to_owned()))
        .and_then(|stamp| timestamp_from_proto(stamp, "started_at"))?;
    validate_started_at(started_at, Utc::now())?;

    Ok(SessionRow {
        client_session_id,
        technique_slug,
        started_at,
        duration_ms: bounded(record.duration_ms, MAX_SESSION_DURATION_MS, "duration_ms")?,
        cycles_completed: bounded(
            record.cycles_completed,
            MAX_CYCLES_PER_SESSION,
            "cycles_completed",
        )?,
        breath_count: bounded(record.breath_count, MAX_BREATHS_PER_SESSION, "breath_count")?,
        completed: record.completed,
    })
}

fn session_to_proto(row: SessionRow) -> Result<pb::SessionRecord, JourneyError> {
    Ok(pb::SessionRecord {
        client_session_id: row.client_session_id.to_string(),
        technique_slug: row.technique_slug,
        started_at: Some(timestamp_to_proto(row.started_at)),
        duration_ms: counted("duration_ms", row.duration_ms)?,
        cycles_completed: counted("cycles_completed", row.cycles_completed)?,
        breath_count: counted("breath_count", row.breath_count)?,
        completed: row.completed,
    })
}

fn bounded(value: u32, maximum: u32, field: &str) -> Result<i32, JourneyError> {
    if value > maximum {
        return Err(JourneyError::Invalid(format!(
            "`{field}` is larger than {maximum}"
        )));
    }

    i32::try_from(value).map_err(|_| JourneyError::Invalid(format!("`{field}` is out of range")))
}

/// Refuses a start time that cannot be a real session.
///
/// Both bounds guard streaks rather than storage: a session dated 1970 would sit
/// harmlessly in the table, but a session dated next year holds a current streak
/// open indefinitely and nothing later can close it.
fn validate_started_at(started_at: DateTime<Utc>, now: DateTime<Utc>) -> Result<(), JourneyError> {
    if started_at.timestamp() < EARLIEST_SESSION_TIMESTAMP {
        return Err(JourneyError::Invalid(
            "`started_at` predates the app".to_owned(),
        ));
    }

    if started_at > now + chrono::Duration::hours(MAX_CLOCK_SKEW_HOURS) {
        return Err(JourneyError::Invalid(
            "`started_at` is in the future".to_owned(),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(started_at: DateTime<Utc>) -> pb::SessionRecord {
        pb::SessionRecord {
            client_session_id: Uuid::nil().to_string(),
            technique_slug: "box-breathing".to_owned(),
            started_at: Some(timestamp_to_proto(started_at)),
            duration_ms: 60_000,
            cycles_completed: 4,
            breath_count: 8,
            completed: true,
        }
    }

    /// A future-dated session would hold a current streak open forever, and
    /// nothing recorded later could close it. Real clock skew is absorbed;
    /// a date next year is not.
    #[test]
    fn a_future_session_is_refused_but_clock_skew_is_not() {
        let now = DateTime::from_timestamp(1_777_000_000, 0).expect("a representable instant");

        assert!(validate_started_at(now + chrono::Duration::hours(1), now).is_ok());
        assert!(matches!(
            validate_started_at(now + chrono::Duration::days(30), now),
            Err(JourneyError::Invalid(_))
        ));
        assert!(matches!(
            validate_started_at(
                DateTime::from_timestamp(0, 0).expect("the epoch is representable"),
                now
            ),
            Err(JourneyError::Invalid(_))
        ));
    }

    /// A session the app cannot have produced fails the batch rather than being
    /// stored — an hour-long "cycle count" of four billion would otherwise sit
    /// in somebody's totals forever.
    #[test]
    fn an_impossible_session_fails_the_batch() {
        let now = Utc::now();

        let mut too_long = record(now);
        too_long.duration_ms = MAX_SESSION_DURATION_MS + 1;
        assert!(matches!(
            session_from_proto(&too_long),
            Err(JourneyError::Invalid(_))
        ));

        let mut no_slug = record(now);
        no_slug.technique_slug = "   ".to_owned();
        assert!(matches!(
            session_from_proto(&no_slug),
            Err(JourneyError::Invalid(_))
        ));

        let mut bad_id = record(now);
        bad_id.client_session_id = "not-a-uuid".to_owned();
        assert!(matches!(
            session_from_proto(&bad_id),
            Err(JourneyError::Invalid(_))
        ));

        assert!(session_from_proto(&record(now)).is_ok());
    }

    fn practice_row(slug: &str, sessions: i64, duration_ms: i64) -> TechniquePracticeRow {
        TechniquePracticeRow {
            technique_slug: slug.to_owned(),
            sessions,
            duration_ms,
        }
    }

    /// The windowed half of a snapshot, with everything reaching outside the
    /// window left empty — which is what the folds below are about. The three
    /// lifetime figures come from their own queries and are exercised end to
    /// end in `tests/e2e/journey/snapshot.rs`, where there is a database to make
    /// them true.
    fn parts(practice: Vec<TechniquePracticeRow>, active_days: i64) -> SnapshotParts {
        SnapshotParts {
            practice,
            active_days,
            bolt: None,
            resting_rate: None,
            totals: TotalsRow {
                sessions: 0,
                breaths: 0,
                duration_ms: 0,
            },
            last_session_at: None,
            streak: None,
        }
    }

    /// The cap bounds the prompt lines, not the arithmetic: the seventh
    /// technique loses its name but never its minutes. A snapshot whose totals
    /// only counted the named entries would understate exactly the scattered
    /// practice the coach should be commenting on.
    #[test]
    fn the_cap_drops_names_but_never_totals() {
        let rows: Vec<TechniquePracticeRow> = (0..7)
            .map(|index| practice_row(&format!("technique-{index}"), 10 - index, 120_000))
            .collect();

        let snapshot = assemble_snapshot(parts(rows, 5)).expect("plausible aggregates assemble");

        assert_eq!(snapshot.by_technique.len(), MAX_SNAPSHOT_TECHNIQUES);
        assert_eq!(
            snapshot.by_technique[0].technique_slug, "technique-0",
            "the repository's busiest-first order is kept"
        );
        assert_eq!(snapshot.sessions, 10 + 9 + 8 + 7 + 6 + 5 + 4);
        assert_eq!(snapshot.minutes, 14, "all seven techniques' minutes count");
        assert_eq!(snapshot.active_days, 5);
    }

    /// The totals divide once over the summed milliseconds, so remainders are
    /// not lost per technique: ninety seconds twice is three minutes, not two.
    #[test]
    fn total_minutes_come_from_summed_milliseconds() {
        let rows = vec![
            practice_row("box-breathing", 1, 90_000),
            practice_row("four-seven-eight", 1, 90_000),
        ];

        let snapshot = assemble_snapshot(parts(rows, 1)).expect("plausible aggregates assemble");

        assert_eq!(snapshot.minutes, 3);
        assert_eq!(
            snapshot.by_technique.iter().map(|t| t.minutes).sum::<u32>(),
            2,
            "each named entry still floors its own remainder"
        );
    }

    /// No history is a zeroed snapshot, not an error — the assistant reads this
    /// for a person who has never breathed, and "no practice recorded yet" is
    /// an answer it has to be able to phrase.
    #[test]
    fn an_empty_history_is_a_zeroed_snapshot() {
        let snapshot = assemble_snapshot(parts(Vec::new(), 0)).expect("an empty history assembles");

        assert_eq!(
            snapshot,
            PracticeSnapshot {
                window_days: 30,
                sessions: 0,
                minutes: 0,
                active_days: 0,
                by_technique: Vec::new(),
                bolt: None,
                resting_rate: None,
                lifetime: None,
                hours_since_last: None,
                streak: None,
            }
        );
    }

    /// A lifetime of nothing is absent rather than a pair of zeroes: "no
    /// practice recorded yet" already says it, and a second line saying zero
    /// sessions would say it twice in the same breath.
    #[test]
    fn a_lifetime_of_nothing_is_absent_rather_than_zero() {
        let mut parts = parts(Vec::new(), 0);
        parts.totals = TotalsRow {
            sessions: 0,
            breaths: 0,
            duration_ms: 0,
        };
        assert_eq!(
            assemble_snapshot(parts)
                .expect("an empty history assembles")
                .lifetime,
            None
        );

        let mut practised = self::parts(Vec::new(), 0);
        practised.totals = TotalsRow {
            sessions: 3,
            breaths: 40,
            duration_ms: 360_000,
        };
        let lifetime = assemble_snapshot(practised)
            .expect("a history assembles")
            .lifetime
            .expect("they have practised");
        assert_eq!((lifetime.sessions, lifetime.minutes), (3, 6));
    }
}
