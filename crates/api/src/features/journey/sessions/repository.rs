//! Session SQL. One append-only table and a window function over it. Streaks
//! are folded here rather than in Rust because they need the whole history to
//! answer, and dragging every row across the wire to count calendar days would
//! be a query that gets slower for the people who use the app most.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use super::super::errors::JourneyError;
use super::types::{PRACTICE_WINDOW_DAYS, SessionCursor};
use crate::features::technique::types::DeliverySurface;
use crate::identity::UserId;

/// One row of `sessions`, in both directions.
pub struct SessionRow {
    pub client_session_id: Uuid,
    pub technique_slug: String,
    pub started_at: DateTime<Utc>,
    pub duration_ms: i32,
    pub cycles_completed: i32,
    pub breath_count: i32,
    pub completed: bool,
    /// The occasion that prescribed the session, `None` when the person picked
    /// the technique themselves.
    pub occasion_slug: Option<String>,
    /// `None` on rows recorded before the column existed, which every reader
    /// treats as full-screen — the only surface any client could deliver then.
    pub surface: Option<DeliverySurface>,
}

/// Everything the journey screen counts, summed over one person's history.
#[derive(Default)]
pub struct TotalsRow {
    pub sessions: i64,
    pub breaths: i64,
    /// Summed rather than pre-divided, so a hundred short sessions do not each
    /// lose their remainder on the way to a minute count.
    pub duration_ms: i64,
}

/// The two streak numbers, which are one query because they are two folds of
/// the same list of days.
#[derive(Default)]
pub struct StreakRow {
    pub current: i32,
    pub best: i32,
}

/// Stores the sessions the server has not seen and reports how many were new.
/// `ON CONFLICT DO NOTHING` on the primary key is the whole of the idempotency:
/// a re-sent batch, a two-device sync and a retried request converge on one row.
/// `RETURNING` counts only the tuples really inserted. One statement over
/// unnested arrays: a fortnight offline is one round trip, and the count atomic.
pub async fn insert_sessions(
    pool: &PgPool,
    user_id: UserId,
    sessions: &[SessionRow],
) -> Result<usize, JourneyError> {
    let ids: Vec<Uuid> = sessions.iter().map(|s| s.client_session_id).collect();
    let slugs: Vec<String> = sessions.iter().map(|s| s.technique_slug.clone()).collect();
    let started_at: Vec<DateTime<Utc>> = sessions.iter().map(|s| s.started_at).collect();
    let durations: Vec<i32> = sessions.iter().map(|s| s.duration_ms).collect();
    let cycles: Vec<i32> = sessions.iter().map(|s| s.cycles_completed).collect();
    let breaths: Vec<i32> = sessions.iter().map(|s| s.breath_count).collect();
    let completed: Vec<bool> = sessions.iter().map(|s| s.completed).collect();
    let occasions: Vec<Option<String>> = sessions.iter().map(|s| s.occasion_slug.clone()).collect();
    let surfaces: Vec<Option<DeliverySurface>> = sessions.iter().map(|s| s.surface).collect();

    let inserted = sqlx::query_scalar!(
        "INSERT INTO sessions (
            user_id, client_session_id, technique_slug, started_at,
            duration_ms, cycles_completed, breath_count, completed,
            occasion_slug, surface
         )
         SELECT $1, s.id, s.slug, s.started_at, s.duration_ms, s.cycles, s.breaths, s.completed,
                s.occasion_slug, s.surface
         FROM UNNEST(
                $2::uuid[], $3::text[], $4::timestamptz[],
                $5::integer[], $6::integer[], $7::integer[], $8::boolean[],
                $9::text[], $10::delivery_surface[]
              ) AS s(id, slug, started_at, duration_ms, cycles, breaths, completed,
                     occasion_slug, surface)
         ON CONFLICT (user_id, client_session_id) DO NOTHING
         RETURNING client_session_id",
        user_id.0,
        &ids,
        &slugs,
        &started_at,
        &durations,
        &cycles,
        &breaths,
        &completed,
        &occasions as &[Option<String>],
        &surfaces as &[Option<DeliverySurface>]
    )
    .fetch_all(pool)
    .await?;

    Ok(inserted.len())
}

/// Removes the caller's sessions with these ids and reports how many went.
/// Scoped to `user_id` in the `WHERE`, not trusted from the ids alone: a
/// `client_session_id` is minted on a device, so an id-only delete would let one
/// caller erase another's history. The affected-row count tells a client whose
/// tombstone list ran ahead of the server there was nothing left to forget.
pub async fn delete_sessions(
    pool: &PgPool,
    user_id: UserId,
    client_session_ids: &[Uuid],
) -> Result<u64, JourneyError> {
    let mut tx = pool.begin().await?;

    // `FOR KEY SHARE` on the caller's row, taking explicitly the lock a session
    // insert already takes through its foreign key. Without it this delete races
    // the sign-in merge's reparent: the merge wins the row locks, the delete
    // sees `user_id` is no longer this caller, matches nothing, and answers OK,
    // so the client drops a tombstone the server never honoured.
    sqlx::query_scalar!(
        "SELECT id FROM users WHERE id = $1 FOR KEY SHARE",
        user_id.0
    )
    .fetch_optional(&mut *tx)
    .await?
    // Behind the lock the delete waits the merge out. A row that comes back
    // gone is that merge, or an account deletion, having committed. Refusing
    // keeps the tombstone alive for a resend under the adopted identity.
    .ok_or(JourneyError::IdentityGone)?;

    let deleted = sqlx::query!(
        "DELETE FROM sessions
         WHERE user_id = $1 AND client_session_id = ANY($2::uuid[])",
        user_id.0,
        client_session_ids
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    Ok(deleted.rows_affected())
}

/// Sums one person's whole history. Deliberately unwindowed: these are lifetime
/// figures, so there is no date predicate and the cost grows with how much
/// somebody has practised. That is the trade the "no counter columns" rule buys
/// — nothing to drift, at the price of a scan on a screen opened a few times a
/// day.
pub async fn totals(pool: &PgPool, user_id: UserId) -> Result<TotalsRow, JourneyError> {
    let row = sqlx::query_as!(
        TotalsRow,
        r#"SELECT
            count(*) AS "sessions!",
            coalesce(sum(breath_count), 0)::bigint AS "breaths!",
            coalesce(sum(duration_ms), 0)::bigint AS "duration_ms!"
         FROM sessions
         WHERE user_id = $1"#,
        user_id.0
    )
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// Folds one person's sessions into a current and a best streak. The local day
/// comes from the caller's offset rather than a stored zone, so a session at
/// 23:30 belongs to the day the person was living in, not to tomorrow in UTC.
/// The current streak accepts a run ending yesterday: a streak is not broken
/// until a whole local day has gone by without a session.
pub async fn streaks(
    pool: &PgPool,
    user_id: UserId,
    utc_offset_minutes: i32,
) -> Result<StreakRow, JourneyError> {
    // The gaps-and-islands fold: number the distinct local days, subtract the
    // row number from the date, and every consecutive run collapses to one
    // constant — so counting runs is a `GROUP BY` rather than a cursor walk.
    let row = sqlx::query_as!(
        StreakRow,
        r#"WITH days AS (
            SELECT DISTINCT
                ((started_at AT TIME ZONE 'UTC') + make_interval(mins => $2))::date AS day
            FROM sessions
            WHERE user_id = $1
        ),
        grouped AS (
            SELECT day, day - (row_number() OVER (ORDER BY day))::integer AS run
            FROM days
        ),
        runs AS (
            SELECT max(day) AS last_day, count(*)::integer AS length
            FROM grouped
            GROUP BY run
        )
        SELECT
            coalesce(max(length) FILTER (
                WHERE last_day >= ((now() AT TIME ZONE 'UTC') + make_interval(mins => $2))::date - 1
            ), 0) AS "current!",
            coalesce(max(length), 0) AS "best!"
        FROM runs"#,
        user_id.0,
        utc_offset_minutes
    )
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// One technique's aggregate over the snapshot window.
pub struct TechniquePracticeRow {
    pub technique_slug: String,
    pub sessions: i64,
    /// Summed rather than pre-divided, for the same reason as [`TotalsRow`].
    pub duration_ms: i64,
}

/// The caller's last [`PRACTICE_WINDOW_DAYS`] of practice, grouped by technique,
/// busiest first. Every group, not the top few: the totals must count all of
/// them, the count is bounded by the caller's own sessions in the window, and
/// the cap on how many are named is the service's. The slug tie-break keeps
/// equal counts off heap order, which would name different techniques per read.
pub async fn recent_practice(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Vec<TechniquePracticeRow>, JourneyError> {
    let rows = sqlx::query_as!(
        TechniquePracticeRow,
        r#"SELECT technique_slug,
                count(*) AS "sessions!",
                sum(duration_ms)::bigint AS "duration_ms!"
         FROM sessions
         WHERE user_id = $1 AND started_at >= now() - make_interval(days => $2)
         GROUP BY technique_slug
         ORDER BY count(*) DESC, technique_slug"#,
        user_id.0,
        i32::from(PRACTICE_WINDOW_DAYS)
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Distinct UTC days with at least one session in the snapshot window. UTC
/// rather than the caller's offset, unlike [`streaks`]: the snapshot feeds
/// offset-insensitive phrasing, and no offset travels on the requests that read
/// it — the why lives on
/// [`PRACTICE_WINDOW_DAYS`](super::types::PRACTICE_WINDOW_DAYS).
pub async fn active_days(pool: &PgPool, user_id: UserId) -> Result<i64, JourneyError> {
    let days = sqlx::query_scalar!(
        r#"SELECT count(DISTINCT (started_at AT TIME ZONE 'UTC')::date) AS "days!"
         FROM sessions
         WHERE user_id = $1 AND started_at >= now() - make_interval(days => $2)"#,
        user_id.0,
        i32::from(PRACTICE_WINDOW_DAYS)
    )
    .fetch_one(pool)
    .await?;

    Ok(days)
}

/// When the caller last began a session, or `None` before their first.
///
/// Unwindowed, unlike [`active_days`]: the answer to "when did you last
/// practise" is worth having precisely when it falls outside the window, and a
/// `max` on the primary ordering is an index read whatever the history.
pub async fn last_session_at(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Option<DateTime<Utc>>, JourneyError> {
    let started_at = sqlx::query_scalar!(
        "SELECT max(started_at) FROM sessions WHERE user_id = $1",
        user_id.0
    )
    .fetch_one(pool)
    .await?;

    Ok(started_at)
}

/// One page of the caller's history, newest first. Ordered on both key columns
/// rather than `started_at` alone: two sessions sharing an instant have no
/// order without it, so a page boundary between them drops one and repeats the
/// other on a restore after a reinstall. `after` seeks the same pair as a
/// row-value comparison, so the planner walks the index from the cursor.
pub async fn recent_sessions(
    pool: &PgPool,
    user_id: UserId,
    limit: i64,
    after: Option<SessionCursor>,
) -> Result<Vec<SessionRow>, JourneyError> {
    let rows = sqlx::query_as!(
        SessionRow,
        r#"SELECT client_session_id, technique_slug, started_at,
                duration_ms, cycles_completed, breath_count, completed,
                occasion_slug, surface AS "surface: DeliverySurface"
         FROM sessions
         WHERE user_id = $1
           AND ($3::timestamptz IS NULL
                OR (started_at, client_session_id) < ($3, $4::uuid))
         ORDER BY started_at DESC, client_session_id DESC
         LIMIT $2"#,
        user_id.0,
        limit,
        after.map(|cursor| cursor.started_at),
        after.map(|cursor| cursor.client_session_id)
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}
