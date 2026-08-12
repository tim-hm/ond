//! The boards, which are the one journey surface that counts people it must not
//! name.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;

use super::{
    ADA, BEA, CAL, GET_LEADERBOARD, board, bolt_score, days_ago, hours_ago, minutes_session, name,
    profile, record, session,
};
use crate::harness::{GrpcWebResponse, TestDatabase, call_grpc_web_with};

/// Ages every board past its time to live, which is the only handle a test has
/// on a schedule measured in wall-clock minutes. Writing the stamp rather than
/// deleting the rows is the point: it drives the production path — a request
/// finds the key stale and re-folds it — instead of a refresh entry point that
/// only tests call.
async fn expire_snapshots(db: &TestDatabase) {
    sqlx::query("UPDATE leaderboard_refresh SET refreshed_at = '-infinity'")
        .execute(&db.pool)
        .await
        .expect("the refresh table exists");
}

/// The opt-in, from both sides. Somebody with no display name is counted in the
/// ranking and named to nobody — they still see exactly where they stand, which
/// is what makes the boards worth opting into rather than a wall someone has to
/// climb first.
#[tokio::test]
async fn a_board_ranks_everyone_and_names_only_the_opted_in() {
    let db = TestDatabase::create("journey_board_visibility").await;

    name(&db, ADA, "Ada").await;
    record(
        &db,
        ADA,
        vec![session(
            "55555555-0000-4000-8000-000000000001",
            hours_ago(1),
        )],
    )
    .await
    .into_ok();

    record(
        &db,
        BEA,
        vec![
            session("55555555-0000-4000-8000-000000000002", hours_ago(1)),
            session("55555555-0000-4000-8000-000000000003", days_ago(1)),
            session("55555555-0000-4000-8000-000000000004", days_ago(2)),
        ],
    )
    .await
    .into_ok();

    let anonymous = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();

    assert_eq!(
        anonymous
            .entries
            .iter()
            .map(|entry| entry.display_name.as_str())
            .collect::<Vec<_>>(),
        vec!["Ada"],
        "the leader is unnamed, so the board shows only the person below them"
    );
    let standing = anonymous.caller.expect("a standing is always returned");
    assert_eq!((standing.rank, standing.value), (Some(1), 3));
    assert!(!standing.listed);

    let named = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    let standing = named.caller.expect("a standing is always returned");
    assert_eq!((standing.rank, standing.value), (Some(2), 1));
    assert!(standing.listed, "a name is the whole of the opt-in");
    assert_eq!(
        named.entries.first().map(|entry| entry.rank),
        Some(2),
        "the rank counts the unnamed leader, so the board starts at two"
    );

    // A third caller who has never practised. Their standing is fetched under
    // their own id rather than found among the entries, so a full board in
    // front of them still answers "no rank yet" about them.
    let unscored = board(
        &db,
        CAL,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(unscored.entries.len(), 1);
    let standing = unscored.caller.expect("a standing is always returned");
    assert_eq!(
        (standing.rank, standing.value, standing.listed),
        (None, 0, false)
    );
}

/// The streak board narrows its fold to people who have breathed recently, which
/// is the only way it stays bounded as the install base grows. What that must
/// not do is change an answer: somebody whose streak ran long and stopped is out
/// of the ranking either way, and somebody still on a run is in it with their
/// whole run counted, however far back it began.
#[tokio::test]
async fn a_streak_board_counts_the_whole_run_and_drops_the_lapsed() {
    let db = TestDatabase::create("journey_board_active_window").await;

    name(&db, ADA, "Ada").await;
    name(&db, BEA, "Bea").await;

    // Ada is on a six-day run reaching back well past the window the fold uses
    // to find her.
    record(
        &db,
        ADA,
        (0..6)
            .map(|day| {
                session(
                    &format!("dddd0000-0000-4000-8000-{day:012}"),
                    days_ago(i64::from(day)),
                )
            })
            .collect(),
    )
    .await
    .into_ok();

    // Bea had a longer run that ended a fortnight ago.
    record(
        &db,
        BEA,
        (10..20)
            .map(|day| {
                session(
                    &format!("dddd0000-0000-4000-8000-{day:012}"),
                    days_ago(i64::from(day)),
                )
            })
            .collect(),
    )
    .await
    .into_ok();

    let streaks = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();

    assert_eq!(
        streaks
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value))
            .collect::<Vec<_>>(),
        vec![("Ada", 6)],
        "the whole run counts, and a run that has lapsed is not a current streak"
    );
}

/// The boards are read from a snapshot, not folded per request. Both halves are
/// worth pinning, and the first is the one that would rot silently: a board that
/// quietly went back to folding live would pass every other test in this file,
/// because a live board and a fresh snapshot give the same answer. The only
/// visible difference is what happens to a board whose underlying sessions have
/// moved since it was folded.
#[tokio::test]
async fn a_board_is_read_from_its_snapshot_until_that_snapshot_expires() {
    let db = TestDatabase::create("journey_board_snapshot").await;

    name(&db, ADA, "Ada").await;
    record(
        &db,
        ADA,
        vec![minutes_session(
            "88888888-0000-4000-8000-000000000001",
            hours_ago(1),
            2,
        )],
    )
    .await
    .into_ok();

    let first = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Minutes30d,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        first.entries.first().map(|entry| entry.value),
        Some(2),
        "the first caller on a board nobody has folded gets it folded for them"
    );

    record(
        &db,
        ADA,
        vec![minutes_session(
            "88888888-0000-4000-8000-000000000002",
            hours_ago(2),
            10,
        )],
    )
    .await
    .into_ok();

    let stale = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Minutes30d,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        stale.entries.first().map(|entry| entry.value),
        Some(2),
        "the second read is answered from the snapshot the first one built"
    );
    assert_eq!(
        stale.caller.expect("a standing is always returned").value,
        2,
        "the caller's own standing comes off the same snapshot, which is what \
         sets how long one may be served for"
    );

    expire_snapshots(&db).await;

    let refreshed = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Minutes30d,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        refreshed.entries.first().map(|entry| entry.value),
        Some(12),
        "an expired snapshot is re-folded by the request that finds it expired"
    );
}

/// The entries a board shows are written by its fold, not ranked against
/// `users` on every request. The read has no way to say so — a freshly folded
/// listing and a live ranking agree — except at the one edge where they differ:
/// somebody who opts in after a fold joins the board when it is next folded,
/// inside the minute the snapshot is allowed to be stale for.
///
/// Worth pinning because a read that quietly went back to ranking every
/// participant per request would pass every other test in this file, while
/// costing a join per participant and two sorts on a call any client may make
/// six hundred times a minute.
#[tokio::test]
async fn a_board_lists_the_entries_its_last_fold_wrote() {
    let db = TestDatabase::create("journey_board_listing").await;

    name(&db, ADA, "Ada").await;
    record(
        &db,
        ADA,
        vec![session(
            "99999999-0000-4000-8000-000000000001",
            hours_ago(1),
        )],
    )
    .await
    .into_ok();

    // Bea is ahead of Ada and has not chosen a name yet.
    record(
        &db,
        BEA,
        vec![
            session("99999999-0000-4000-8000-000000000002", hours_ago(1)),
            session("99999999-0000-4000-8000-000000000003", days_ago(1)),
        ],
    )
    .await
    .into_ok();

    let folded = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        folded
            .entries
            .iter()
            .map(|entry| entry.display_name.as_str())
            .collect::<Vec<_>>(),
        vec!["Ada"]
    );

    name(&db, BEA, "Bea").await;

    let cached = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        cached
            .entries
            .iter()
            .map(|entry| entry.display_name.as_str())
            .collect::<Vec<_>>(),
        vec!["Ada"],
        "the entries come back as the last fold wrote them"
    );

    expire_snapshots(&db).await;

    let refolded = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        refolded
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.rank))
            .collect::<Vec<_>>(),
        vec![("Bea", 1), ("Ada", 2)],
        "and the fold that finds the snapshot stale writes the opt-in into them"
    );

    // Opting back out is the direction that must not wait for a fold. The
    // listing holds who is shown; the name itself is read live, so clearing it
    // takes somebody off the board on the next request rather than the next
    // minute.
    name(&db, BEA, "").await;

    let withdrawn = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        withdrawn
            .entries
            .iter()
            .map(|entry| entry.display_name.as_str())
            .collect::<Vec<_>>(),
        vec!["Ada"],
        "a cleared name leaves the board at once, not at the next fold"
    );
}

/// The age-band scope draws a different population from the same rows, and asks
/// for something the caller may not have said — which is a precondition rather
/// than a malformed request, so the client can offer the question instead of
/// correcting a field.
#[tokio::test]
async fn the_age_band_scope_compares_like_with_like() {
    let db = TestDatabase::create("journey_board_age_band").await;

    profile(&db, ADA, "Ada", pb::BirthYearBand::Born1980s).await;
    profile(&db, BEA, "Bea", pb::BirthYearBand::Born1990s).await;
    profile(&db, CAL, "", pb::BirthYearBand::Born1980s).await;

    record(
        &db,
        ADA,
        vec![session(
            "66666666-0000-4000-8000-000000000001",
            hours_ago(1),
        )],
    )
    .await
    .into_ok();
    record(
        &db,
        BEA,
        vec![
            session("66666666-0000-4000-8000-000000000002", hours_ago(1)),
            session("66666666-0000-4000-8000-000000000003", days_ago(1)),
            session("66666666-0000-4000-8000-000000000004", days_ago(2)),
        ],
    )
    .await
    .into_ok();
    record(
        &db,
        CAL,
        vec![
            session("66666666-0000-4000-8000-000000000005", hours_ago(1)),
            session("66666666-0000-4000-8000-000000000006", days_ago(1)),
        ],
    )
    .await
    .into_ok();

    let global = board(
        &db,
        CAL,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        global
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.rank))
            .collect::<Vec<_>>(),
        vec![("Bea", 1), ("Ada", 3)]
    );
    assert_eq!(
        global.caller.expect("a standing").rank,
        Some(2),
        "two days is second of three globally"
    );

    let banded = board(
        &db,
        CAL,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::AgeBand,
    )
    .await
    .into_ok();
    assert_eq!(
        banded
            .entries
            .iter()
            .map(|entry| entry.display_name.as_str())
            .collect::<Vec<_>>(),
        vec!["Ada"],
        "Bea is in another decade and drops out of the population entirely"
    );
    assert_eq!(banded.caller.expect("a standing").rank, Some(1));

    let unbanded: GrpcWebResponse<pb::GetLeaderboardResponse> = call_grpc_web_with(
        db.app(),
        GET_LEADERBOARD,
        &pb::GetLeaderboardRequest {
            board: pb::LeaderboardBoard::Streak as i32,
            scope: pb::LeaderboardScope::AgeBand as i32,
            utc_offset_minutes: 0,
        },
        &[(USER_ID_HEADER, "6a1f0000-0000-4000-8000-000000000009")],
    )
    .await;
    assert_eq!(unbanded.status, tonic::Code::FailedPrecondition as i32);
}

/// Answering the decade question is the one profile change that moves somebody
/// between boards, and it happens exactly when a caller has just been refused
/// the age-band scope — so it lands, by design, on a board that was folded a
/// moment ago without them in any band.
///
/// The board that comes back is the one they can be shown: their own score, no
/// rank in a population they were not ranked in, and everyone who is. The
/// failure this pins is not hypothetical — ranking at fold time introduced it,
/// and it read as an internal error on the request right after the answer.
#[tokio::test]
async fn a_band_answered_after_the_fold_still_answers() {
    let db = TestDatabase::create("journey_board_band_after_fold").await;

    profile(&db, ADA, "Ada", pb::BirthYearBand::Born1980s).await;
    name(&db, BEA, "Bea").await;

    record(
        &db,
        ADA,
        vec![session(
            "bbbbbbbb-0000-4000-8000-000000000001",
            hours_ago(1),
        )],
    )
    .await
    .into_ok();
    record(
        &db,
        BEA,
        vec![session(
            "bbbbbbbb-0000-4000-8000-000000000002",
            hours_ago(1),
        )],
    )
    .await
    .into_ok();

    // Bea folds the board while she has no band, is refused the age-band scope,
    // and answers the question the refusal exists to prompt.
    let global = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(global.entries.len(), 2);

    let refused: GrpcWebResponse<pb::GetLeaderboardResponse> = call_grpc_web_with(
        db.app(),
        GET_LEADERBOARD,
        &pb::GetLeaderboardRequest {
            board: pb::LeaderboardBoard::Streak as i32,
            scope: pb::LeaderboardScope::AgeBand as i32,
            utc_offset_minutes: 0,
        },
        &[(USER_ID_HEADER, BEA)],
    )
    .await;
    assert_eq!(refused.status, tonic::Code::FailedPrecondition as i32);

    profile(&db, BEA, "Bea", pb::BirthYearBand::Born1980s).await;

    let banded = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::AgeBand,
    )
    .await
    .into_ok();
    let standing = banded.caller.expect("a standing is always returned");
    assert_eq!(
        (standing.rank, standing.value),
        (None, 1),
        "the score is hers; the rank is one the fold has not worked out yet"
    );

    expire_snapshots(&db).await;

    let refolded = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Streak,
        pb::LeaderboardScope::AgeBand,
    )
    .await
    .into_ok();
    assert_eq!(
        refolded.caller.expect("a standing").rank,
        Some(1),
        "and the next fold puts her in the band she answered"
    );
}

/// The other two boards, which share the streak board's ranking shape and differ
/// only in what they measure. Worth pinning because each has its own `scored`
/// query: the minutes board floors at a whole minute, and the BOLT board ranks a
/// best rather than a total.
#[tokio::test]
async fn the_minutes_and_bolt_boards_measure_their_own_thing() {
    let db = TestDatabase::create("journey_board_measures").await;

    name(&db, ADA, "Ada").await;
    name(&db, BEA, "Bea").await;

    // Ada breathes twice for two minutes; Bea once for five.
    record(
        &db,
        ADA,
        vec![
            minutes_session("77777777-0000-4000-8000-000000000001", hours_ago(1), 2),
            minutes_session("77777777-0000-4000-8000-000000000002", days_ago(1), 2),
        ],
    )
    .await
    .into_ok();
    record(
        &db,
        BEA,
        vec![minutes_session(
            "77777777-0000-4000-8000-000000000003",
            hours_ago(1),
            5,
        )],
    )
    .await
    .into_ok();

    let minutes = board(
        &db,
        ADA,
        pb::LeaderboardBoard::Minutes30d,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        minutes
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value))
            .collect::<Vec<_>>(),
        vec![("Bea", 5), ("Ada", 4)]
    );

    bolt_score(&db, ADA, 30).await.into_ok();
    bolt_score(&db, BEA, 18).await.into_ok();

    let scores = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Bolt,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();
    assert_eq!(
        scores
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value))
            .collect::<Vec<_>>(),
        vec![("Ada", 30), ("Bea", 18)]
    );
    assert_eq!(scores.caller.expect("a standing").rank, Some(2));
}

/// The pause board stops distinguishing people at the settled pause, so holding
/// on past the first urge earns nothing on it.
///
/// The mirror of the resting rate's floor, and the reason either measurement can
/// be ranked at all: without it, "longest I held my breath" is the maximal-hold
/// contest every screen of the test tells people not to run — and the app would
/// be arguing both sides, safety in the copy and a prize on the board.
///
/// Their own histories are untouched by it. Both people keep the pause they
/// actually measured; it is the ranking that cannot see past the ceiling.
#[tokio::test]
async fn the_pause_board_ties_everybody_who_reaches_a_settled_pause() {
    let db = TestDatabase::create("journey_board_pause_ceiling").await;

    name(&db, ADA, "Ada").await;
    name(&db, BEA, "Bea").await;

    // Both past the ceiling, a minute apart. Ada held nearly twice as long.
    bolt_score(&db, ADA, 95).await.into_ok();
    let bea = bolt_score(&db, BEA, 52).await.into_ok();

    let scores = board(
        &db,
        BEA,
        pb::LeaderboardBoard::Bolt,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();

    assert_eq!(
        scores
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value))
            .collect::<Vec<_>>(),
        vec![("Ada", 40), ("Bea", 40)],
        "both are folded to the ceiling rather than ranked against each other"
    );
    assert_eq!(
        scores
            .entries
            .iter()
            .map(|entry| entry.rank)
            .collect::<Vec<_>>(),
        vec![1, 1],
        "a tie at the top, not an order the longer hold won"
    );
    assert_eq!(
        bea.best_seconds, 52,
        "the person's own record keeps what they measured"
    );
}
