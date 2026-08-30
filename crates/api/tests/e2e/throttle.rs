//! What a hostile caller gets, driven at the volume that makes the answer mean
//! something: several hundred requests through the real router — a budget
//! asserted at three would pass against a limiter switched off above ten.
//! Every test builds its router with the limiter's clock stopped, and none may
//! stop: a burst straddling a minute window is served twice, which failed about one run in seven.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use api::throttle::{FORWARDED_FOR, NEW_IDENTITIES_PER_WINDOW, REQUESTS_PER_WINDOW};
use axum::Router;
use uuid::Uuid;

use crate::harness::{GET_LEADERBOARD, GrpcWebResponse, TestDatabase, call_grpc_web_with};

/// `tonic::Code::ResourceExhausted`, which is what both budgets refuse with.
const RESOURCE_EXHAUSTED: i32 = 8;

/// Two callers with distinct keys, so a test can assert one is rationed without
/// the other being touched. Any string works — the key is whatever Caddy wrote,
/// and nothing parses it as an address.
const HOSTILE: &str = "198.51.100.9";
const BYSTANDER: &str = "203.0.113.4";

/// The nth identity an attacker would invent. Counted rather than random
/// because `uuid` here carries no generator feature on purpose — a server able
/// to mint an id would invite an identity the client never sees — and a stable
/// value leaves rows somebody can go and look at.
fn invented(n: u32) -> String {
    Uuid::from_u128(0x7717_0000_0000_4000_8000_0000_0000_0000 | u128::from(n)).to_string()
}

/// One leaderboard call as the given caller from the given address. Takes the
/// `Router` rather than the `TestDatabase` because the budgets live on the
/// state that router holds: every `TestDatabase::app*` call builds a fresh
/// one, which would make a loop here count to one over and over.
async fn board(app: Router, forwarded_for: &str, user: &str) -> i32 {
    let response: GrpcWebResponse<pb::GetLeaderboardResponse> = call_grpc_web_with(
        app,
        GET_LEADERBOARD,
        &pb::GetLeaderboardRequest {
            board: pb::LeaderboardBoard::Streak as i32,
            scope: pb::LeaderboardScope::Global as i32,
            utc_offset_minutes: 0,
        },
        &[(USER_ID_HEADER, user), (FORWARDED_FOR, forwarded_for)],
    )
    .await;

    response.status
}

/// How many `users` rows exist, which is the number the 10 GiB volume cares
/// about.
async fn user_count(db: &TestDatabase) -> i64 {
    sqlx::query_scalar!(r#"SELECT count(*) AS "count!" FROM users"#)
        .fetch_one(&db.pool)
        .await
        .expect("the count is readable")
}

/// The attack in the issue, run: a loop over fresh UUIDs against the public
/// surface. The assertion is on the table rather than the responses, because
/// the table is what was actually unbounded. Rows are capped at the identity
/// budget while the caller keeps getting answers — this refuses *identity
/// creation*, not traffic, and a caller who stops inventing people is served normally.
#[tokio::test]
async fn a_loop_over_fresh_uuids_stops_creating_rows() {
    let db = TestDatabase::create("throttle_fresh_uuids").await;
    let app = db.app_with_stopped_throttle();

    let attempts = NEW_IDENTITIES_PER_WINDOW * 20;
    let mut refused = 0;
    for attempt in 0..attempts {
        if board(app.clone(), HOSTILE, &invented(attempt)).await == RESOURCE_EXHAUSTED {
            refused += 1;
        }
    }

    assert_eq!(
        user_count(&db).await,
        i64::from(NEW_IDENTITIES_PER_WINDOW),
        "a fresh UUID per request should stop producing rows at the identity budget"
    );
    assert_eq!(
        refused,
        attempts - NEW_IDENTITIES_PER_WINDOW,
        "every attempt past the budget should be refused rather than quietly served"
    );
}

/// The other half, bounding the leaderboard *query* rather than the rows: one
/// established user hammering the most expensive read in the schema. The bound
/// asserted here is the whole of what stands between a `t4g.small` and
/// somebody's `for` loop, so it is asserted at the real budget rather than a
/// convenient fraction of it.
#[tokio::test]
async fn an_established_caller_hammering_the_boards_is_cut_off() {
    let db = TestDatabase::create("throttle_leaderboard_flood").await;
    let app = db.app_with_stopped_throttle();
    let user = invented(0);

    let mut served = 0;
    for _ in 0..REQUESTS_PER_WINDOW + 50 {
        if board(app.clone(), HOSTILE, &user).await != RESOURCE_EXHAUSTED {
            served += 1;
        }
    }

    assert_eq!(
        served, REQUESTS_PER_WINDOW,
        "the leaderboard should be answerable exactly as often as the request budget allows"
    );
}

/// The failure mode a rate limit introduces, pinned: one caller spending
/// everything must not spend it on anybody else's behalf. Both budgets are
/// checked, because they are keyed the same way and a mistake in that keying
/// would look identical in each — a global counter dressed up as a per-caller
/// one passes every test above.
#[tokio::test]
async fn a_flood_from_one_address_does_not_ration_another() {
    let db = TestDatabase::create("throttle_bystander").await;
    let app = db.app_with_stopped_throttle();

    let flood = NEW_IDENTITIES_PER_WINDOW * 2;
    for attempt in 0..flood {
        board(app.clone(), HOSTILE, &invented(attempt)).await;
    }
    assert_eq!(
        board(app.clone(), HOSTILE, &invented(flood)).await,
        RESOURCE_EXHAUSTED,
        "the hostile caller should be out of identity budget"
    );

    assert_ne!(
        board(app.clone(), BYSTANDER, &invented(flood + 1)).await,
        RESOURCE_EXHAUSTED,
        "somebody else's first launch should still be able to create their identity"
    );
}

/// A forged `X-Forwarded-For` must not buy a fresh allowance. Caddy appends
/// the peer it accepted to whatever the client sent, so the value arrives as
/// `<forgery>, <real>` and only the right-hand end is ours — reading the other
/// end would hand every attacker an unlimited supply of identities for the
/// price of one header.
#[tokio::test]
async fn a_forged_forwarded_for_prefix_buys_nothing() {
    let db = TestDatabase::create("throttle_forged_prefix").await;
    let app = db.app_with_stopped_throttle();

    for attempt in 0..NEW_IDENTITIES_PER_WINDOW * 3 {
        // A different claimed origin every time, with Caddy's entry after it.
        let forwarded = format!("10.0.0.{attempt}, {HOSTILE}");
        board(app.clone(), &forwarded, &invented(attempt)).await;
    }

    assert_eq!(
        user_count(&db).await,
        i64::from(NEW_IDENTITIES_PER_WINDOW),
        "rotating the left-hand entries should not refill the budget"
    );
}
