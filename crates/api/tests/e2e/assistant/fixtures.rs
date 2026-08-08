//! What every assistant test builds its world out of: the two streaming route
//! constants, the two identities, the scripted-model call helpers, and the
//! profile and practice rows the prompt is assembled from.
//!
//! Here rather than in each file, on `journey::fixtures`'s terms: all four
//! suites subscribe a caller and ask the same three RPCs, and four copies of
//! `recommend()` would be four places for a test's setup to drift.

use std::sync::Arc;

use api::assistant::{ModelClient, ModelError, ModelRequest, ModelStream};
use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use chrono::Utc;

use crate::harness::{
    self, TestDatabase, call_grpc_web_stream_with, call_grpc_web_with, subscribe,
};

pub(crate) const EXPLAIN_TECHNIQUE: &str = "/ond.v1.AssistantService/ExplainTechnique";
pub(crate) const CHAT: &str = "/ond.v1.AssistantService/Chat";

pub(crate) const USER: &str = "5c4d3e2f-0000-4000-8000-000000000001";
pub(crate) const OTHER_USER: &str = "5c4d3e2f-0000-4000-8000-000000000002";

/// A model that starts answering and then breaks — the one shape
/// [`ScriptedModel`] cannot express, because a scripted reply either fails the
/// call or answers it and this case does both.
pub(crate) struct HalfAnswer;

#[tonic::async_trait]
impl ModelClient for HalfAnswer {
    async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
        Err(ModelError::Failed("down".to_owned()))
    }

    async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
        Ok(Box::pin(tokio_stream::iter(vec![
            Ok("First the mechanism.".to_owned()),
            Err(ModelError::Failed("the stream broke mid-answer".to_owned())),
        ])))
    }
}

/// Asks for a recommendation as somebody who is allowed to reach the model.
///
/// The subscription is part of the helper rather than repeated at the top of
/// every test, because this suite is about what the model says and not about
/// who may ask it — that gate is `entitlement.rs`'s, and a test here that forgot
/// the setup would fail as though the assistant were broken. Cheap enough to
/// repeat: it is one upsert per call.
pub(crate) async fn recommend(
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
pub(crate) async fn recommend_with_health(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    health: Option<pb::HealthContext>,
) -> pb::GetRecommendationResponse {
    subscribe(&db.pool, user, "COACH").await;

    harness::recommend(db.app_with_model(model), user, health).await
}

pub(crate) async fn explain(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    slug: &str,
) -> crate::harness::GrpcWebStream<pb::ExplainTechniqueResponse> {
    explain_with_health(db, model, user, slug, None).await
}

pub(crate) async fn explain_with_health(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    slug: &str,
    health: Option<pb::HealthContext>,
) -> crate::harness::GrpcWebStream<pb::ExplainTechniqueResponse> {
    subscribe(&db.pool, user, "COACH").await;

    call_grpc_web_stream_with(
        db.app_with_model(model),
        EXPLAIN_TECHNIQUE,
        &pb::ExplainTechniqueRequest {
            technique_slug: slug.to_owned(),
            health_context: health,
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

/// Sends one chat message as a Coach subscriber, on [`recommend`]'s terms: the
/// subscription is the helper's business because this suite is about what the
/// coach says, not who may ask it.
pub(crate) async fn chat(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    history: Vec<pb::ChatTurn>,
    message: &str,
) -> crate::harness::GrpcWebStream<pb::ChatResponse> {
    subscribe(&db.pool, user, "COACH").await;

    call_grpc_web_stream_with(
        db.app_with_model(model),
        CHAT,
        &pb::ChatRequest {
            history,
            message: message.to_owned(),
            health_context: None,
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub(crate) fn chat_turn(role: pb::ChatRole, text: &str) -> pb::ChatTurn {
    pb::ChatTurn {
        role: role as i32,
        text: text.to_owned(),
    }
}

/// Stores goals through the real `ProfileService`, so the rows the assistant
/// reads are the ones onboarding writes.
pub(crate) async fn set_goals(db: &TestDatabase, user: &str, goals: &[pb::TechniqueGoal]) {
    set_profile(
        db,
        user,
        goals,
        pb::Gender::Unspecified,
        pb::BirthYearBand::Unspecified,
    )
    .await;
}

pub(crate) async fn set_profile(
    db: &TestDatabase,
    user: &str,
    goals: &[pb::TechniqueGoal],
    gender: pb::Gender,
    band: pb::BirthYearBand,
) {
    let response: crate::harness::GrpcWebResponse<pb::UpdateProfileResponse> = call_grpc_web_with(
        db.app(),
        "/ond.v1.ProfileService/UpdateProfile",
        &pb::UpdateProfileRequest {
            profile: Some(pb::Profile {
                goals: goals.iter().map(|goal| *goal as i32).collect(),
                experience_level: pb::ExperienceLevel::New as i32,
                gender: gender as i32,
                birth_year_band: band as i32,
                ..pb::Profile::default()
            }),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await;

    response.into_ok();
}

/// Records one recent session per `(slug, minutes)` entry through the real
/// `JourneyService`, so the practice the assistant reads is the practice the
/// app records — hostile slugs included, which is the point of the boundary
/// test above.
pub(crate) async fn record_practice(db: &TestDatabase, user: &str, sessions: &[(&str, u32)]) {
    let records = sessions
        .iter()
        .enumerate()
        .map(|(index, (slug, minutes))| pb::SessionRecord {
            client_session_id: format!("7b2e0000-0000-4000-8000-{index:012}"),
            technique_slug: (*slug).to_owned(),
            started_at: Some(prost_timestamp_hours_ago(
                i64::try_from(index).expect("a handful of sessions") + 1,
            )),
            duration_ms: minutes * 60_000,
            cycles_completed: 4,
            breath_count: 8,
            completed: true,
        })
        .collect();

    let response: crate::harness::GrpcWebResponse<pb::RecordSessionsResponse> = call_grpc_web_with(
        db.app(),
        "/ond.v1.JourneyService/RecordSessions",
        &pb::RecordSessionsRequest { sessions: records },
        &[(USER_ID_HEADER, user)],
    )
    .await;

    response.into_ok();
}

pub(crate) async fn record_bolt(db: &TestDatabase, user: &str, seconds: u32) {
    let response: crate::harness::GrpcWebResponse<pb::RecordBoltScoreResponse> =
        call_grpc_web_with(
            db.app(),
            "/ond.v1.JourneyService/RecordBoltScore",
            &pb::RecordBoltScoreRequest {
                client_score_id: format!("7b2e0000-0000-4000-9000-{seconds:012}"),
                seconds,
                measured_at: None,
            },
            &[(USER_ID_HEADER, user)],
        )
        .await;

    response.into_ok();
}

pub(crate) fn prost_timestamp_hours_ago(hours: i64) -> prost_types::Timestamp {
    let instant = Utc::now() - chrono::Duration::hours(hours);
    prost_types::Timestamp {
        seconds: instant.timestamp(),
        nanos: 0,
    }
}
