//! Leaderboard SQL in two halves: the fold and the read.
//!
//! The fold runs on refresh, once per board per day boundary: one row per person
//! into `leaderboard_snapshot`, ranked, then the twenty each scope shows into
//! `leaderboard_listing`. It stays in SQL because ranking needs every row.

use sqlx::{PgPool, Postgres, Transaction};

use super::super::bolt;
use super::super::errors::JourneyError;
use super::super::resting_rate;
use super::service::LEADERBOARD_LIMIT;
use super::types::LeaderboardBoard;
use crate::features::profile::types::BirthYearBand;
use crate::identity::UserId;

/// One entry as a board shows it, in the order it is shown.
pub struct LeaderboardEntryRow {
    pub display_name: String,
    pub value: i32,
    /// Counts everybody ahead, including the people with no name to show, and
    /// ties — so a board's ranks are neither dense nor its own row numbers.
    pub rank: i32,
}

/// Where the caller stands on a board, whether or not they are listed on it.
pub struct LeaderboardStandingRow {
    pub value: i32,
    /// The rank for the scope that was asked about, or `None` when the last
    /// fold did not rank this person in it — which is what somebody who has
    /// just answered the decade question, or changed their answer, sees until
    /// the board is folded again. Their score is still theirs; it is the
    /// standing against this population that does not exist yet.
    pub rank: Option<i32>,
    /// Whether the caller has a name for others to see them under. Read from
    /// `users` rather than from the listing, because it answers "will anybody
    /// see me" — true from the moment a name is chosen, rather than from the
    /// next fold.
    pub listed: bool,
}

/// The entries one scope of one board shows, in position order.
///
/// Two statements rather than one over `band IS NOT DISTINCT FROM $3`: that
/// operator has no btree strategy, so the band drops out of the index condition
/// into a filter. Names join live, so clearing one leaves the board next request.
pub async fn listing(
    pool: &PgPool,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
    band: Option<BirthYearBand>,
) -> Result<Vec<LeaderboardEntryRow>, JourneyError> {
    let rows = match band {
        None => {
            sqlx::query_as!(
                LeaderboardEntryRow,
                r#"SELECT u.display_name AS "display_name!", s.value,
                          s.global_rank AS "rank!"
                   FROM leaderboard_listing l
                   JOIN users u ON u.id = l.user_id
                   JOIN leaderboard_snapshot s
                     ON s.board = l.board
                    AND s.utc_offset_minutes = l.utc_offset_minutes
                    AND s.user_id = l.user_id
                   WHERE l.board = $1 AND l.utc_offset_minutes = $2 AND l.band IS NULL
                     AND u.display_name IS NOT NULL
                   ORDER BY l.position"#,
                board as _,
                utc_offset_minutes
            )
            .fetch_all(pool)
            .await?
        }
        Some(band) => {
            sqlx::query_as!(
                LeaderboardEntryRow,
                r#"SELECT u.display_name AS "display_name!", s.value,
                          s.band_rank AS "rank!"
                   FROM leaderboard_listing l
                   JOIN users u ON u.id = l.user_id
                   JOIN leaderboard_snapshot s
                     ON s.board = l.board
                    AND s.utc_offset_minutes = l.utc_offset_minutes
                    AND s.user_id = l.user_id
                   WHERE l.board = $1 AND l.utc_offset_minutes = $2 AND l.band = $3
                     AND u.display_name IS NOT NULL
                   ORDER BY l.position"#,
                board as _,
                utc_offset_minutes,
                band as _
            )
            .fetch_all(pool)
            .await?
        }
    };

    Ok(rows)
}

/// The caller's own row on a board, or `None` before they have a score on it.
///
/// Keyed by identity, not searched for among the entries. The band is compared,
/// not merely tested for null: the fold ranked the band this person held then,
/// and a disagreement gives no rank rather than one on a board they have left.
pub async fn standing(
    pool: &PgPool,
    caller: UserId,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
    band: Option<BirthYearBand>,
) -> Result<Option<LeaderboardStandingRow>, JourneyError> {
    let row = sqlx::query_as!(
        LeaderboardStandingRow,
        r#"SELECT s.value,
                  CASE WHEN $4::birth_year_band IS NULL THEN s.global_rank
                       WHEN s.band = $4 THEN s.band_rank
                  END AS rank,
                  u.display_name IS NOT NULL AS "listed!"
           FROM leaderboard_snapshot s
           JOIN users u ON u.id = s.user_id
           WHERE s.board = $2 AND s.utc_offset_minutes = $3 AND s.user_id = $1"#,
        caller.0,
        board as _,
        utc_offset_minutes,
        band as _
    )
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Whether a board's snapshot is young enough to serve.
///
/// Deliberately outside the refresh transaction and taking no lock. This is the
/// answer on almost every request, and the moment it needs a row lock every
/// caller reading the same board queues behind every other.
pub async fn is_fresh(
    pool: &PgPool,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
    ttl_seconds: f64,
) -> Result<bool, JourneyError> {
    let fresh = sqlx::query_scalar!(
        r#"SELECT EXISTS (
            SELECT 1 FROM leaderboard_refresh
            WHERE board = $1 AND utc_offset_minutes = $2
              AND refreshed_at > now() - make_interval(secs => $3)
        ) AS "fresh!""#,
        board as _,
        utc_offset_minutes,
        ttl_seconds
    )
    .fetch_one(pool)
    .await?;

    Ok(fresh)
}

/// Re-folds one board at one day boundary, unless somebody else just did.
///
/// One transaction around the `leaderboard_refresh` row, both mutex and clock,
/// so a burst folds once. The lock is required, not an economy: the fold deletes
/// and reinserts a key's rows, and two interleaved under READ COMMITTED collide.
pub async fn refresh(
    pool: &PgPool,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
    ttl_seconds: f64,
) -> Result<(), JourneyError> {
    let mut tx = pool.begin().await?;

    sqlx::query!(
        "INSERT INTO leaderboard_refresh (board, utc_offset_minutes, refreshed_at)
         VALUES ($1, $2, '-infinity')
         ON CONFLICT (board, utc_offset_minutes) DO NOTHING",
        board as _,
        utc_offset_minutes
    )
    .execute(&mut *tx)
    .await?;

    let fresh = sqlx::query_scalar!(
        r#"SELECT refreshed_at > now() - make_interval(secs => $3) AS "fresh!"
           FROM leaderboard_refresh
           WHERE board = $1 AND utc_offset_minutes = $2
           FOR UPDATE"#,
        board as _,
        utc_offset_minutes,
        ttl_seconds
    )
    .fetch_one(&mut *tx)
    .await?;

    if fresh {
        // Somebody folded this key while this transaction waited for the lock.
        // Rolled back rather than committed: the row it may have inserted above
        // is `-infinity`, which would otherwise persist as a key claiming never
        // to have been folded next to the rows that were.
        tx.rollback().await?;
        return Ok(());
    }

    sqlx::query!(
        "DELETE FROM leaderboard_snapshot WHERE board = $1 AND utc_offset_minutes = $2",
        board as _,
        utc_offset_minutes
    )
    .execute(&mut *tx)
    .await?;

    fold(&mut tx, board, utc_offset_minutes).await?;
    rank(&mut tx, board, utc_offset_minutes).await?;
    list(&mut tx, board, utc_offset_minutes).await?;

    sqlx::query!(
        "UPDATE leaderboard_refresh SET refreshed_at = now()
         WHERE board = $1 AND utc_offset_minutes = $2",
        board as _,
        utc_offset_minutes
    )
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

/// Computes one board's scores into the snapshot.
///
/// The four statements are written out rather than composed: `sqlx::query!`
/// checks a literal string against the real schema at compile time.
async fn fold(
    tx: &mut Transaction<'_, Postgres>,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
) -> Result<(), JourneyError> {
    match board {
        LeaderboardBoard::Streak => {
            // `recent` bounds how many people are folded, not how many rows each
            // contributes. Three UTC days is the smallest superset of "local
            // yesterday or later" at every offset, and the final `WHERE` still
            // applies the exact local-day test.
            sqlx::query!(
                "INSERT INTO leaderboard_snapshot (board, utc_offset_minutes, user_id, value)
                 WITH recent AS (
                     SELECT DISTINCT user_id
                     FROM sessions
                     WHERE started_at >= now() - interval '3 days'
                 ),
                 days AS (
                     SELECT DISTINCT
                         s.user_id,
                         ((s.started_at AT TIME ZONE 'UTC') + make_interval(mins => $1))::date AS day
                     FROM sessions s
                     JOIN recent r ON r.user_id = s.user_id
                 ),
                 grouped AS (
                     SELECT user_id, day,
                            day - (row_number() OVER (PARTITION BY user_id ORDER BY day))::integer AS run
                     FROM days
                 ),
                 runs AS (
                     SELECT user_id, max(day) AS last_day, count(*)::integer AS length
                     FROM grouped
                     GROUP BY user_id, run
                 )
                 SELECT 'STREAK'::leaderboard_board, $1, user_id, max(length)
                 FROM runs
                 WHERE last_day >= ((now() AT TIME ZONE 'UTC') + make_interval(mins => $1))::date - 1
                 GROUP BY user_id",
                utc_offset_minutes
            )
            .execute(&mut **tx)
            .await?;
        }
        LeaderboardBoard::Minutes30d => {
            // `HAVING` drops anybody short of a whole minute rather than
            // recording them at zero. A board of zeroes is worse than a short
            // board.
            sqlx::query!(
                "INSERT INTO leaderboard_snapshot (board, utc_offset_minutes, user_id, value)
                 SELECT 'MINUTES_30D'::leaderboard_board, $1, user_id,
                        (sum(duration_ms) / 60000)::integer
                 FROM sessions
                 WHERE started_at >= now() - interval '30 days'
                 GROUP BY user_id
                 HAVING sum(duration_ms) >= 60000",
                utc_offset_minutes
            )
            .execute(&mut **tx)
            .await?;
        }
        LeaderboardBoard::Bolt => {
            // `least` is this board's ceiling, the mirror of the resting rate's
            // floor below and there for the same reason: everybody at or above
            // the settled pause is folded to it and ties there, so holding
            // longer earns nothing. See `bolt::service::BOARD_CEILING_SECONDS`.
            sqlx::query!(
                "INSERT INTO leaderboard_snapshot (board, utc_offset_minutes, user_id, value)
                 SELECT 'BOLT'::leaderboard_board, $1, user_id,
                        least(max(seconds), $2)
                 FROM bolt_scores
                 GROUP BY user_id",
                utc_offset_minutes,
                bolt::service::BOARD_CEILING_SECONDS
            )
            .execute(&mut **tx)
            .await?;
        }
        LeaderboardBoard::RestingRate => {
            // `greatest` is the board's ceiling on what pushing can earn, not a
            // display choice: everybody at or below the resonance floor is
            // folded to it and ties there. See
            // `resting_rate::service::BOARD_FLOOR_BREATHS_PER_MINUTE`.
            sqlx::query!(
                "INSERT INTO leaderboard_snapshot (board, utc_offset_minutes, user_id, value)
                 SELECT 'RESTING_RATE'::leaderboard_board, $1, user_id,
                        greatest(min(breaths_per_minute), $2)
                 FROM resting_rates
                 GROUP BY user_id",
                utc_offset_minutes,
                resting_rate::service::BOARD_FLOOR_BREATHS_PER_MINUTE
            )
            .execute(&mut **tx)
            .await?;
        }
    }

    Ok(())
}

/// Writes each person's standing into the rows [`fold`] just inserted.
///
/// One statement per board; direction comes from [`LeaderboardBoard::ranking_sign`].
/// A separate pass adds about 400 ms to a 500 ms fold at 50k people. Ranking
/// inside the four folds costs 35 ms, but is four places to rank the wrong way.
async fn rank(
    tx: &mut Transaction<'_, Postgres>,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
) -> Result<(), JourneyError> {
    sqlx::query!(
        "UPDATE leaderboard_snapshot s
         SET global_rank = r.global_rank, band_rank = r.band_rank, band = r.band
         FROM (
             SELECT x.user_id, u.birth_year_band AS band,
                    rank() OVER (ORDER BY x.value * $3 DESC)::integer AS global_rank,
                    CASE WHEN u.birth_year_band IS NULL THEN NULL
                         ELSE rank() OVER (
                             PARTITION BY u.birth_year_band ORDER BY x.value * $3 DESC
                         )::integer
                    END AS band_rank
             FROM leaderboard_snapshot x
             JOIN users u ON u.id = x.user_id
             WHERE x.board = $1 AND x.utc_offset_minutes = $2
         ) r
         WHERE s.board = $1 AND s.utc_offset_minutes = $2 AND s.user_id = r.user_id",
        board as _,
        utc_offset_minutes,
        board.ranking_sign()
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}

/// Materialises which people every scope of this board shows, and in what order.
///
/// One pass produces all seven listings: everyone and each of the six bands.
/// Only people with a display name are listed; `position` orders them among
/// themselves while the snapshot's rank still counts the anonymous people ahead.
async fn list(
    tx: &mut Transaction<'_, Postgres>,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
) -> Result<(), JourneyError> {
    sqlx::query!(
        "DELETE FROM leaderboard_listing WHERE board = $1 AND utc_offset_minutes = $2",
        board as _,
        utc_offset_minutes
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query!(
        "INSERT INTO leaderboard_listing (board, utc_offset_minutes, band, position, user_id)
         WITH named AS (
             SELECT s.user_id, u.display_name, u.birth_year_band,
                    s.global_rank, s.band_rank
             FROM leaderboard_snapshot s
             JOIN users u ON u.id = s.user_id
             WHERE s.board = $1 AND s.utc_offset_minutes = $2
               AND u.display_name IS NOT NULL
         ),
         scoped AS (
             SELECT NULL::birth_year_band AS band,
                    row_number() OVER (ORDER BY global_rank, display_name)::integer AS position,
                    user_id
             FROM named
             UNION ALL
             SELECT birth_year_band,
                    row_number() OVER (
                        PARTITION BY birth_year_band ORDER BY band_rank, display_name
                    )::integer,
                    user_id
             FROM named
             WHERE birth_year_band IS NOT NULL
         )
         SELECT $1::leaderboard_board, $2, band, position, user_id
         FROM scoped
         WHERE position <= $3",
        board as _,
        utc_offset_minutes,
        LEADERBOARD_LIMIT
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}
