//! Business logic — picks a board, resolves who it is drawn from, and converts
//! the ranking onto the wire.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use std::time::Duration;

use sqlx::PgPool;

use super::super::errors::JourneyError;
use super::super::wire::validated_offset;
use super::repository::{self, LeaderboardEntryRow, LeaderboardStandingRow};
use super::types::{LeaderboardBoard, LeaderboardScope};
use crate::features::profile::service as profile;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire::counted;

/// How many named entries a board returns.
///
/// Read by `super::repository::list`, which applies it when the listing is
/// written rather than when it is read — so there is one place that decides how
/// long a board is, on the same terms as the two board ceilings the fold reads
/// out of their own services.
pub(super) const LEADERBOARD_LIMIT: i32 = 20;

/// How long a board may be served from the snapshot before the next request
/// re-folds it.
///
/// A minute, not the several the boards would tolerate if they only showed
/// other people. The same query answers "where do I stand", and somebody who
/// has just finished a session and opened the tab is the one reader who can
/// tell a stale board from a live one — their own number is the one they know.
///
/// What this replaces is a fold per request. `crate::throttle` bounds the rate
/// one caller may ask at — six hundred a minute — and says nothing about how
/// many callers there are; this makes the fold rate a property of the clock
/// instead, at most once a minute per board per day boundary however hard
/// anybody pulls.
const SNAPSHOT_TTL: Duration = Duration::from_mins(1);

/// The day boundary the boards without a local-day question are folded at.
///
/// A rolling thirty days and a personal best are the same number at every
/// offset, so those two boards are materialised once rather than once per
/// offset somebody happens to be standing in. Zero is a real offset and their
/// answer there is their answer everywhere, so this narrows nothing.
const NO_DAY_BOUNDARY: i32 = 0;

/// A board's leading entries, plus where the caller stands on it.
///
/// The opt-in runs one way: only people who have chosen a display name appear in
/// `entries`, and everyone with a score is counted in the ranking. Somebody
/// anonymous is therefore invisible to others and still knows their own
/// position, which is what makes the boards worth opting into rather than a wall
/// to climb first.
///
/// The age-band scope needs a birth-year band the caller may never have given.
/// That is a `FAILED_PRECONDITION` rather than a malformed request: the client's
/// answer is to offer the decade question, not to correct a field.
///
/// A board is never served unfolded. The snapshot is checked before it is read,
/// and a key that is stale or has never existed is refreshed first — so an
/// empty `entries` still means what `journey_service.proto` says it means,
/// nobody has opted in yet, rather than "the fold has not happened". The cost
/// of that guarantee lands on the first caller after each expiry and on nobody
/// else.
///
/// The entries and the caller's standing are two statements with no transaction
/// around them, so a re-fold landing between them serves a board from one fold
/// and a standing from the next. Both are answers the caller could have had a
/// moment earlier or later, they disagree by at most one minute's practice, and
/// the alternative is holding a transaction open across the read every client
/// makes most often.
pub async fn get_leaderboard(
    pool: &PgPool,
    user_id: UserId,
    request: pb::GetLeaderboardRequest,
) -> Result<pb::GetLeaderboardResponse, JourneyError> {
    let board = board_from_proto(request.board)?;
    let scope = scope_from_proto(request.scope)?;

    let band = match scope {
        LeaderboardScope::Global => None,
        LeaderboardScope::AgeBand => Some(
            profile::birth_year_band(pool, user_id)
                .await?
                .ok_or(JourneyError::AgeBandUnset)?,
        ),
    };

    let utc_offset_minutes = match board {
        LeaderboardBoard::Streak => validated_offset(request.utc_offset_minutes)?,
        LeaderboardBoard::Minutes30d | LeaderboardBoard::Bolt | LeaderboardBoard::RestingRate => {
            NO_DAY_BOUNDARY
        }
    };

    let ttl_seconds = SNAPSHOT_TTL.as_secs_f64();
    if !repository::is_fresh(pool, board, utc_offset_minutes, ttl_seconds).await? {
        repository::refresh(pool, board, utc_offset_minutes, ttl_seconds).await?;
    }

    let entries = repository::listing(pool, board, utc_offset_minutes, band).await?;
    let standing = repository::standing(pool, user_id, board, utc_offset_minutes, band).await?;

    to_leaderboard_response(entries, standing)
}

/// Puts the board's entries and the caller's own row onto the wire.
///
/// The two arrive from two queries rather than one result set the caller is
/// searched for in: somebody in the top twenty appears in both, once as an entry
/// and once as their standing, and nothing has to decide which row is theirs.
///
/// Every narrowing here is fallible. A rank or a value the wire cannot carry
/// fails the call rather than dropping that person from the board or zeroing
/// their score: a board short by one row is indistinguishable from a board with
/// one fewer participant, and a zero reads as "they have not practised".
fn to_leaderboard_response(
    entries: Vec<LeaderboardEntryRow>,
    standing: Option<LeaderboardStandingRow>,
) -> Result<pb::GetLeaderboardResponse, JourneyError> {
    let caller = match standing {
        // A score with no rank is somebody the last fold did not rank in this
        // scope — they answered the decade question, or changed their answer,
        // since it ran. Their own number is still true, and the rank they are
        // not told is the one they do not have yet.
        Some(standing) => pb::LeaderboardStanding {
            rank: standing
                .rank
                .map(|rank| counted("rank", rank))
                .transpose()?,
            value: counted("value", standing.value)?,
            listed: standing.listed,
        },
        // Present even when the caller has nothing to rank, so the client can
        // tell "no score yet" from "no answer" without a second field.
        None => pb::LeaderboardStanding {
            rank: None,
            value: 0,
            listed: false,
        },
    };

    let entries = entries
        .into_iter()
        .map(|entry| {
            Ok(pb::LeaderboardEntry {
                rank: counted("rank", entry.rank)?,
                display_name: entry.display_name,
                value: counted("value", entry.value)?,
            })
        })
        .collect::<Result<Vec<_>, JourneyError>>()?;

    Ok(pb::GetLeaderboardResponse {
        entries,
        caller: Some(caller),
    })
}

fn board_from_proto(raw: i32) -> Result<LeaderboardBoard, JourneyError> {
    match pb::LeaderboardBoard::try_from(raw) {
        Ok(pb::LeaderboardBoard::Streak) => Ok(LeaderboardBoard::Streak),
        Ok(pb::LeaderboardBoard::Minutes30d) => Ok(LeaderboardBoard::Minutes30d),
        Ok(pb::LeaderboardBoard::Bolt) => Ok(LeaderboardBoard::Bolt),
        Ok(pb::LeaderboardBoard::RestingRate) => Ok(LeaderboardBoard::RestingRate),
        Ok(pb::LeaderboardBoard::Unspecified) | Err(_) => Err(JourneyError::Invalid(format!(
            "`{raw}` is not a board this server knows"
        ))),
    }
}

fn scope_from_proto(raw: i32) -> Result<LeaderboardScope, JourneyError> {
    match pb::LeaderboardScope::try_from(raw) {
        Ok(pb::LeaderboardScope::Global) => Ok(LeaderboardScope::Global),
        Ok(pb::LeaderboardScope::AgeBand) => Ok(LeaderboardScope::AgeBand),
        Ok(pb::LeaderboardScope::Unspecified) | Err(_) => Err(JourneyError::Invalid(format!(
            "`{raw}` is not a scope this server knows"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(rank: i32, value: i32, display_name: &str) -> LeaderboardEntryRow {
        LeaderboardEntryRow {
            display_name: display_name.to_owned(),
            value,
            rank,
        }
    }

    /// Every board and scope the proto can carry has to be either a real case or
    /// a rejection — a zero value silently becoming STREAK would answer a
    /// question nobody asked.
    #[test]
    fn an_unspecified_board_or_scope_is_refused() {
        assert!(matches!(
            board_from_proto(pb::LeaderboardBoard::Unspecified as i32),
            Err(JourneyError::Invalid(_))
        ));
        assert!(matches!(
            scope_from_proto(pb::LeaderboardScope::Unspecified as i32),
            Err(JourneyError::Invalid(_))
        ));
        assert!(board_from_proto(pb::LeaderboardBoard::Bolt as i32).is_ok());
        assert!(scope_from_proto(pb::LeaderboardScope::AgeBand as i32).is_ok());
    }

    /// A row the wire cannot carry fails the call. The shape this replaced
    /// dropped that person from the board and zeroed the score, and neither is
    /// falsifiable from a client: a board short by one row looks exactly like a
    /// board with one fewer participant.
    #[test]
    fn a_row_that_does_not_fit_fails_the_board_rather_than_shortening_it() {
        assert!(matches!(
            to_leaderboard_response(vec![entry(-1, 5, "Ada")], None),
            Err(JourneyError::Inconsistent(_))
        ));
        assert!(matches!(
            to_leaderboard_response(vec![entry(1, -5, "Ada")], None),
            Err(JourneyError::Inconsistent(_))
        ));

        let listed = to_leaderboard_response(vec![entry(1, 5, "Ada")], None)
            .expect("a representable row is served");
        assert_eq!(listed.entries.len(), 1);
        assert_eq!(
            listed.caller.expect("a standing is always returned").rank,
            None,
            "somebody with no score on a board still gets an answer about themselves"
        );
    }

    /// Somebody the last fold did not rank in this scope — the decade question
    /// answered or changed since it ran — keeps their score and is told they
    /// have no rank yet. The alternative that was here first refused the call,
    /// which turned answering a profile question into a minute of failing
    /// boards.
    #[test]
    fn a_scored_caller_the_fold_has_not_ranked_yet_keeps_their_score() {
        let standing = LeaderboardStandingRow {
            value: 5,
            rank: None,
            listed: true,
        };

        let response = to_leaderboard_response(Vec::new(), Some(standing))
            .expect("an unranked score is an answer, not a failure");
        let caller = response.caller.expect("a standing is always returned");

        assert_eq!((caller.rank, caller.value, caller.listed), (None, 5, true));
    }
}
