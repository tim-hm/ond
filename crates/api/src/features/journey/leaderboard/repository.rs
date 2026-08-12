//! Leaderboard SQL, in two halves that used to be one.
//!
//! The fold — four rankings' worth of gaps-and-islands, rolling sums and
//! per-person extremes — runs on refresh, once per board per day boundary. It
//! lands one narrow row per person in `leaderboard_snapshot`, ranks those rows,
//! and writes which twenty people each scope shows into `leaderboard_listing`.
//! The read is that listing plus the caller's own row, both reached by key, and
//! touches neither the measurement tables nor anybody else's ranking.
//!
//! The fold stays in SQL for the reason it always did: ranking needs every
//! candidate row to answer, and dragging the install base's history across the
//! wire to sort it would be a query that gets slower for exactly the people who
//! use the app most. What changed is who pays for it — the read used to rank
//! every participant and join `users` once per person on every request, so the
//! sixty-second snapshot bounded the fold and nothing else.

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
/// An index scan of the listing's twenty rows for the key, then a keyed lookup
/// of each person's name and score. Two statements rather than one over
/// `band IS NOT DISTINCT FROM $3`, because that operator has no btree strategy:
/// the band drops out of the index condition and back into a filter, which
/// reads every scope's rows for the key and re-sorts what the index had already
/// ordered.
///
/// The names are joined live rather than folded into the listing, so somebody
/// who clears their display name leaves the board on their next request rather
/// than at the next fold — the same reason the ranking counts them and the
/// listing does not name them.
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
/// Keyed by identity rather than searched for among the entries, which is what
/// makes it the caller's row rather than whichever row happens to carry a
/// matching id.
///
/// The band is compared rather than merely tested for null, because the fold
/// ranked this person in whichever band they were in at the time and the
/// question is being asked about the band they are in now. When the two
/// disagree — the decade question answered or changed since the last fold —
/// the answer is no rank rather than the rank they held on a board they have
/// left, and the next fold, at most a minute away, settles it.
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
/// The whole thing is one transaction around the `leaderboard_refresh` row,
/// which serves as both the mutex and the clock. A request that finds the key
/// stale creates the row if it is missing, locks it, and re-asks the question
/// it already asked outside the lock — so a burst of callers arriving on an
/// expired board produces exactly one fold and a queue of no-ops behind it,
/// rather than one fold each.
///
/// The lock is not merely an economy. The fold deletes a key's rows and
/// reinserts them, and two such transactions interleaved under READ COMMITTED
/// each delete the rows visible to their own snapshot and then collide on the
/// primary key.
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
/// The statements share one shape and differ only in what they measure.
/// They are written out rather than composed because `sqlx::query!` checks a
/// literal string against the real schema at compile time, and a string built
/// at runtime would trade that guarantee for the removal of about ten lines.
///
/// The streak fold's `recent` CTE is what keeps it bounded. Only somebody who
/// breathed within the last local day or two can hold a current streak, so the
/// gaps-and-islands fold runs over that population rather than over everyone
/// who has ever used the app. It still reads each of those people's whole
/// history — a run's length is not knowable from its tail — so what the window
/// bounds is how many people are folded, not how many rows each contributes.
/// Three UTC days is the smallest window that is a superset of "local yesterday
/// or later" at every offset from -12:00 to +14:00; the final `WHERE` still
/// applies the exact local-day test, so the widening changes no answer.
///
/// The minutes board's `HAVING` drops anybody short of a whole minute rather
/// than recording them at zero — a board of zeroes is worse than a short board.
async fn fold(
    tx: &mut Transaction<'_, Postgres>,
    board: LeaderboardBoard,
    utc_offset_minutes: i32,
) -> Result<(), JourneyError> {
    match board {
        LeaderboardBoard::Streak => {
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
/// One statement for every board, because by this point the four folds have
/// become the same narrow table and differ only in which direction "better"
/// points — see [`LeaderboardBoard::ranking_sign`].
///
/// Both rankings are computed here rather than at read time because a person's
/// rank changes only when the board is re-folded, and each person has exactly
/// one band: storing their own band's rank beside their global one is two
/// columns, not the per-band copy of every row `0013_leaderboard_snapshot.sql`
/// argued against. `band_rank` is null for somebody who has not given a band,
/// whose band is a population nobody can ask about.
///
/// A second pass over rows [`fold`] wrote a moment ago, which is the deliberate
/// half of the trade: measured at 50k participants it adds about 400 ms to a
/// fold that already costs 500 ms, and leaves a second row version for
/// autovacuum. Ranking inside each of the four folds instead costs about 35 ms
/// — but it is four copies of this window pair, and four places for one board
/// to start ranking the wrong way round. The fold runs at most once a minute per
/// board per day boundary; a divergence would be permanent.
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

/// Materialises which people every scope of this board will show, and in what
/// order.
///
/// One pass over the key's rows produces all seven listings — everyone, and each
/// of the six birth-year bands — so the join to `users` that used to run once
/// per participant per request now runs once per fold.
///
/// Only people who have chosen a display name are listed, and `position` orders
/// them among themselves while the snapshot's rank keeps counting the anonymous
/// people ahead of them. That is the opt-in the boards are built on: a board can
/// start at rank two.
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
