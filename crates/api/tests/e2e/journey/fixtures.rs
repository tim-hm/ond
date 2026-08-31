//! What every journey test builds its world out of.
//!
//! Here rather than in each file because all four suites record sessions and
//! identities the same way, and four copies of `session()` would be four places
//! for a test's arithmetic to drift.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use chrono::{DateTime, Duration, Utc};

use crate::harness::{
    DELETE_SESSIONS, GET_JOURNEY, GET_LEADERBOARD, GrpcWebResponse, TestDatabase, UPDATE_PROFILE,
    call_grpc_web_with, prost_timestamp,
};

/// Stable identities, so a failing test leaves rows someone can go and look at.
pub(super) const ADA: &str = "6a1f0000-0000-4000-8000-000000000001";
pub(super) const BEA: &str = "6a1f0000-0000-4000-8000-000000000002";
pub(super) const CAL: &str = "6a1f0000-0000-4000-8000-000000000003";

pub(super) fn session(id: &str, started_at: DateTime<Utc>) -> pb::SessionRecord {
    minutes_session(id, started_at, 2)
}

pub(super) fn minutes_session(
    id: &str,
    started_at: DateTime<Utc>,
    minutes: u32,
) -> pb::SessionRecord {
    pb::SessionRecord {
        client_session_id: id.to_owned(),
        technique_slug: "box-breathing".to_owned(),
        started_at: Some(prost_timestamp(started_at)),
        duration_ms: minutes * 60_000,
        cycles_completed: 4,
        breath_count: 8,
        completed: true,
        occasion_slug: None,
        surface: pb::DeliverySurface::Unspecified as i32,
    }
}

/// Exactly `days` × 24 hours ago, which in a fixed offset is the same clock time
/// that many local days back — so a test can name a local day without knowing
/// what time it is when it runs.
pub(super) fn days_ago(days: i64) -> DateTime<Utc> {
    Utc::now() - Duration::days(days)
}

pub(super) async fn delete(
    db: &TestDatabase,
    user: &str,
    client_session_ids: Vec<String>,
) -> GrpcWebResponse<pb::DeleteSessionsResponse> {
    call_grpc_web_with(
        db.app(),
        DELETE_SESSIONS,
        &pb::DeleteSessionsRequest { client_session_ids },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub(super) async fn journey(
    db: &TestDatabase,
    user: &str,
    utc_offset_minutes: i32,
) -> GrpcWebResponse<pb::GetJourneyResponse> {
    journey_page(db, user, utc_offset_minutes, None, None).await
}

pub(super) async fn journey_page(
    db: &TestDatabase,
    user: &str,
    utc_offset_minutes: i32,
    limit: Option<u32>,
    page_token: Option<String>,
) -> GrpcWebResponse<pb::GetJourneyResponse> {
    journey_request(
        db,
        user,
        pb::GetJourneyRequest {
            utc_offset_minutes,
            limit,
            page_token,
            sessions_only: false,
        },
    )
    .await
}

/// For the tests that care what the request said, rather than only what came
/// back — `sessions_only` above all, which nothing else here sets.
pub(super) async fn journey_request(
    db: &TestDatabase,
    user: &str,
    request: pb::GetJourneyRequest,
) -> GrpcWebResponse<pb::GetJourneyResponse> {
    call_grpc_web_with(db.app(), GET_JOURNEY, &request, &[(USER_ID_HEADER, user)]).await
}

/// Reads a board as a subscriber, which is the only way a board can be read.
/// The subscription is written here rather than in each test because none of
/// these suites is about the gate — a `subscribe` line at the top of thirty
/// tests would be thirty chances to forget one and read a `PERMISSION_DENIED`
/// as an empty board. The gate is pinned by the one test that skips this helper.
pub(super) async fn board(
    db: &TestDatabase,
    user: &str,
    board: pb::LeaderboardBoard,
    scope: pb::LeaderboardScope,
) -> GrpcWebResponse<pb::GetLeaderboardResponse> {
    db.given_subscriber(user).await;

    call_grpc_web_with(
        db.app(),
        GET_LEADERBOARD,
        &pb::GetLeaderboardRequest {
            board: board as i32,
            scope: scope as i32,
            utc_offset_minutes: 0,
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub(super) async fn name(db: &TestDatabase, user: &str, display_name: &str) {
    profile(db, user, display_name, pb::BirthYearBand::Unspecified).await;
}

pub(super) async fn profile(
    db: &TestDatabase,
    user: &str,
    display_name: &str,
    band: pb::BirthYearBand,
) {
    let response: GrpcWebResponse<pb::UpdateProfileResponse> = call_grpc_web_with(
        db.app(),
        UPDATE_PROFILE,
        &pb::UpdateProfileRequest {
            profile: Some(pb::Profile {
                display_name: display_name.to_owned(),
                birth_year_band: band as i32,
                ..pb::Profile::default()
            }),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await;

    response.into_ok();
}
