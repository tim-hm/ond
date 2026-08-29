//! Resting-rate measurements over the wire, and the one board that reads
//! backwards.

use api::proto::ond::v1 as pb;

use super::{ADA, BEA, board, name, resting_rate, resting_rate_with};
use crate::harness::TestDatabase;

/// "Best" is *lowest* here, which is the whole of what makes this measurement
/// different from the pause beside it. A faster rate afterwards must not
/// overwrite the slowest on record, and the verdict is the server's for the
/// reason it is there: a client that was offline for three counts does not hold
/// the history to compare against.
#[tokio::test]
async fn a_resting_rate_is_a_personal_best_only_when_it_is_slower() {
    let db = TestDatabase::create("journey_rate_best").await;

    let first = resting_rate(&db, ADA, 16).await.into_ok();
    assert_eq!(
        (first.lowest_breaths_per_minute, first.is_personal_best),
        (16, true)
    );

    let slower = resting_rate(&db, ADA, 11).await.into_ok();
    assert_eq!(
        (slower.lowest_breaths_per_minute, slower.is_personal_best),
        (11, true)
    );

    let faster = resting_rate(&db, ADA, 14).await.into_ok();
    assert_eq!(
        (faster.lowest_breaths_per_minute, faster.is_personal_best),
        (11, false),
        "a faster rate is not a best, however recent"
    );
}

/// The bounds are where "fewest breaths in a minute" stops being a competition
/// somebody can win by not breathing. Three below the floor is a held breath
/// rather than a reading, and anything above the ceiling was not measured at
/// rest; both are refused rather than clamped, because a stored number the
/// person did not measure is worse than a rejected one.
#[tokio::test]
async fn a_rate_outside_what_resting_breathing_does_is_refused() {
    let db = TestDatabase::create("journey_rate_bounds").await;

    for implausible in [0, 3, 61, 20_000] {
        let refused = resting_rate(&db, ADA, implausible).await;
        assert_eq!(
            refused.status,
            tonic::Code::InvalidArgument as i32,
            "{implausible} breaths a minute is not a resting rate"
        );
    }

    assert_eq!(count_resting_rates(&db).await, 0);

    resting_rate(&db, ADA, 4).await.into_ok();
    resting_rate(&db, ADA, 60).await.into_ok();
    assert_eq!(count_resting_rates(&db).await, 2, "the edges are readings");
}

/// Rates drain through the same opportunistic queue as sessions and pauses, so
/// a resend has to be as free here as it is there — and duplicates hide behind
/// `min(breaths_per_minute)` on every board exactly as they hide behind `max`.
#[tokio::test]
async fn a_resent_rate_does_not_become_a_second_one() {
    let db = TestDatabase::create("journey_rate_idempotent").await;
    let id = "88888888-0000-4000-8000-000000000001";

    let first = resting_rate_with(&db, ADA, id, 13, None).await.into_ok();
    assert_eq!(
        (first.lowest_breaths_per_minute, first.is_personal_best),
        (13, true)
    );

    let resent = resting_rate_with(&db, ADA, id, 13, None).await.into_ok();
    assert_eq!(resent.lowest_breaths_per_minute, 13);
    assert!(
        !resent.is_personal_best,
        "the rate is already on record, so it cannot beat it"
    );
    assert_eq!(count_resting_rates(&db).await, 1);

    // Another person may hold the same client id without colliding: the key is
    // the pair, not the id alone.
    resting_rate_with(&db, BEA, id, 15, None).await.into_ok();
    assert_eq!(count_resting_rates(&db).await, 2);

    let malformed = resting_rate_with(&db, ADA, "not-a-uuid", 12, None).await;
    assert_eq!(malformed.status, tonic::Code::InvalidArgument as i32);
}

/// The board that reads backwards, and the floor that stops it being a
/// breath-hold contest under another name. Two claims in one test because they
/// are one design: slowest leads, and everybody at or below the resonance
/// frequency ties at the top — the only way to move on this board is to come
/// down *to* what the practice is aiming at rather than past it.
#[tokio::test]
async fn the_resting_rate_board_leads_with_the_slowest_and_floors_at_resonance() {
    let db = TestDatabase::create("journey_rate_board").await;

    name(&db, ADA, "Ada").await;
    name(&db, BEA, "Bea").await;
    resting_rate(&db, ADA, 5).await.into_ok();
    resting_rate(&db, BEA, 6).await.into_ok();
    resting_rate(&db, BEA, 18).await.into_ok();

    let ranked = board(
        &db,
        ADA,
        pb::LeaderboardBoard::RestingRate,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();

    assert_eq!(
        ranked
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value, entry.rank))
            .collect::<Vec<_>>(),
        vec![("Ada", 6, 1), ("Bea", 6, 1)],
        "five is carried onto the board as six, and the two tie there"
    );
    let standing = ranked.caller.expect("a standing is always returned");
    assert_eq!((standing.value, standing.rank), (6, Some(1)));
}

/// A rate above the floor ranks behind one at it, which is what makes the board
/// worth reading at all — the tie at the top is the ceiling on the contest, not
/// the whole of the board.
#[tokio::test]
async fn a_faster_resting_rate_ranks_behind_a_slower_one() {
    let db = TestDatabase::create("journey_rate_board_order").await;

    name(&db, ADA, "Ada").await;
    name(&db, BEA, "Bea").await;
    resting_rate(&db, ADA, 15).await.into_ok();
    resting_rate(&db, BEA, 9).await.into_ok();

    let ranked = board(
        &db,
        ADA,
        pb::LeaderboardBoard::RestingRate,
        pb::LeaderboardScope::Global,
    )
    .await
    .into_ok();

    assert_eq!(
        ranked
            .entries
            .iter()
            .map(|entry| (entry.display_name.as_str(), entry.value))
            .collect::<Vec<_>>(),
        vec![("Bea", 9), ("Ada", 15)]
    );
    assert_eq!(
        ranked.caller.expect("a standing").rank,
        Some(2),
        "Ada breathes faster"
    );
}

async fn count_resting_rates(db: &TestDatabase) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM resting_rates")
        .fetch_one(&db.pool)
        .await
        .expect("the resting_rates table is readable")
}
