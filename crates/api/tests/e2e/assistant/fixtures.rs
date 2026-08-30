//! What every assistant test builds its world out of. Here rather than in
//! each file because all four suites ask the same two RPCs. Everybody here is
//! subscribed, and the upsert lives in the helpers: a caller who has bought
//! nothing never reaches the model, so tests about what the coach *says* would
//! otherwise assert against the refusal. One test deliberately skips these helpers to pin that.

use std::sync::Arc;

use api::assistant::ModelClient;
use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;

use crate::harness::CHAT;
use crate::harness::{
    self, TestDatabase, UPDATE_PROFILE, call_grpc_web_stream_with, call_grpc_web_with,
};

pub(super) const USER: &str = "5c4d3e2f-0000-4000-8000-000000000001";
pub(super) const OTHER_USER: &str = "5c4d3e2f-0000-4000-8000-000000000002";

/// Asks for a recommendation as a subscriber.
///
/// The subscription is arranged here so no test in this suite has to say it:
/// what may reach the model is `entitlement/`'s question, and this suite is
/// about what the model says once it is reached.
pub(super) async fn recommend(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
) -> pb::GetRecommendationResponse {
    recommend_with_health(db, model, user, None).await
}

/// [`recommend`], plus the health context an opted-in phone would attach.
///
/// Separate rather than a parameter on every call site, for the same reason
/// the harness pairs `call_grpc_web` with `call_grpc_web_with`: most of this
/// suite is not about health, and should not say so on every line.
pub(super) async fn recommend_with_health(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    health: Option<pb::HealthContext>,
) -> pb::GetRecommendationResponse {
    db.given_subscriber(user).await;

    harness::recommend(db.app_with_model(model), user, health).await
}

/// Sends one chat message as a subscriber, on [`recommend`]'s terms and for the
/// same reason: this suite is about what the coach says, not who may ask it.
pub(super) async fn chat(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    history: Vec<pb::ChatTurn>,
    message: &str,
) -> crate::harness::GrpcWebStream<pb::ChatResponse> {
    db.given_subscriber(user).await;

    call_grpc_web_stream_with(
        db.app_with_model(model),
        CHAT,
        &pb::ChatRequest {
            history,
            message: message.to_owned(),
            health_context: None,
            utc_offset_minutes: None,
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub(super) fn chat_turn(role: pb::ChatRole, text: &str) -> pb::ChatTurn {
    pb::ChatTurn {
        role: role as i32,
        text: text.to_owned(),
        offered_slug: String::new(),
    }
}

/// The text of one chat chunk — empty for an offer chunk, which carries none.
pub(super) fn chunk_text(chunk: &pb::ChatResponse) -> &str {
    match chunk.payload.as_ref() {
        Some(pb::chat_response::Payload::Text(text)) => text,
        _ => "",
    }
}

/// Stores goals through the real `ProfileService`, so the rows the assistant
/// reads are the ones onboarding writes.
pub(super) async fn set_goals(db: &TestDatabase, user: &str, goals: &[pb::TechniqueGoal]) {
    set_profile(
        db,
        user,
        goals,
        pb::Gender::Unspecified,
        pb::BirthYearBand::Unspecified,
        "",
    )
    .await;
}

/// Stores a whole profile through the real `ProfileService`. `given_name` is
/// empty for all but the one test about the name reaching the per-caller half
/// — a name written unconditionally would be present in every other suite's
/// profile without any of them asking for it.
pub(super) async fn set_profile(
    db: &TestDatabase,
    user: &str,
    goals: &[pb::TechniqueGoal],
    gender: pb::Gender,
    band: pb::BirthYearBand,
    given_name: &str,
) {
    let response: crate::harness::GrpcWebResponse<pb::UpdateProfileResponse> = call_grpc_web_with(
        db.app(),
        UPDATE_PROFILE,
        &pb::UpdateProfileRequest {
            profile: Some(pb::Profile {
                goals: goals.iter().map(|goal| *goal as i32).collect(),
                experience_level: pb::ExperienceLevel::New as i32,
                gender: gender as i32,
                birth_year_band: band as i32,
                given_name: given_name.to_owned(),
                ..pb::Profile::default()
            }),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await;

    response.into_ok();
}

/// One saved exercise, on `record_practice`'s terms: the harness owns the RPC
/// because two suites drive it, and this names the one thing the prompt reads.
pub(super) async fn save_exercise(db: &TestDatabase, user: &str, name: &str) {
    harness::save_technique(db, user, name).await.into_ok();
}

/// Records one recent session per `(slug, minutes)` entry through the real
/// `JourneyService`, so the practice the assistant reads is the practice the
/// app records — hostile slugs included, which is the point of the boundary
/// test above.
pub(super) async fn record_practice(db: &TestDatabase, user: &str, sessions: &[(&str, u32)]) {
    let records = sessions
        .iter()
        .enumerate()
        .map(|(index, (slug, minutes))| pb::SessionRecord {
            client_session_id: format!("7b2e0000-0000-4000-8000-{index:012}"),
            technique_slug: (*slug).to_owned(),
            started_at: Some(harness::prost_timestamp(harness::hours_ago(
                i64::try_from(index).expect("a handful of sessions") + 1,
            ))),
            duration_ms: minutes * 60_000,
            cycles_completed: 4,
            breath_count: 8,
            completed: true,
            occasion_slug: None,
            surface: pb::DeliverySurface::Unspecified as i32,
        })
        .collect();

    harness::record(db, user, records).await.into_ok();
}

pub(super) async fn record_bolt(db: &TestDatabase, user: &str, seconds: u32) {
    harness::bolt_score(db, user, seconds).await.into_ok();
}
