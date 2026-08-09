//! What every assistant test builds its world out of: the two streaming route
//! constants, the two identities, the scripted-model call helpers, and the
//! profile and practice rows the prompt is assembled from.
//!
//! Here rather than in each file, on `journey::fixtures`'s terms: all four
//! suites ask the same three RPCs, and four copies of `recommend()` would be
//! four places for a test's setup to drift.
//!
//! Nobody here is subscribed, which is not an omission — the assistant is free,
//! so a caller who has bought nothing is the caller this suite is about. These
//! helpers used to upsert a Coach row first, and dropping that is what makes
//! them exercise the shape production actually serves.

use std::sync::Arc;

use api::assistant::{ModelChunk, ModelClient, ModelError, ModelRequest, ModelStream};
use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;

use crate::harness::{self, TestDatabase, call_grpc_web_stream_with, call_grpc_web_with};

pub(super) const EXPLAIN_TECHNIQUE: &str = "/ond.v1.AssistantService/ExplainTechnique";
pub(super) const CHAT: &str = "/ond.v1.AssistantService/Chat";

pub(super) const USER: &str = "5c4d3e2f-0000-4000-8000-000000000001";
pub(super) const OTHER_USER: &str = "5c4d3e2f-0000-4000-8000-000000000002";

/// A model that starts answering and then breaks — the one shape
/// [`ScriptedModel`] cannot express, because a scripted reply either fails the
/// call or answers it and this case does both.
pub(super) struct HalfAnswer;

#[tonic::async_trait]
impl ModelClient for HalfAnswer {
    async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
        Err(ModelError::Failed("down".to_owned()))
    }

    async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
        Ok(Box::pin(tokio_stream::iter(vec![
            Ok(ModelChunk::Text("First the mechanism.".to_owned())),
            Err(ModelError::Failed("the stream broke mid-answer".to_owned())),
        ])))
    }
}

/// Asks for a recommendation as somebody who has bought nothing.
///
/// Which is everybody: the assistant is free, so there is no subscription for
/// this helper to arrange and no gate for a test here to trip over. What may
/// reach the model is `entitlement.rs`'s question; this suite is about what the
/// model says once it is reached.
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
    harness::recommend(db.app_with_model(model), user, health).await
}

pub(super) async fn explain(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    slug: &str,
) -> crate::harness::GrpcWebStream<pb::ExplainTechniqueResponse> {
    explain_with_health(db, model, user, slug, None).await
}

pub(super) async fn explain_with_health(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    slug: &str,
    health: Option<pb::HealthContext>,
) -> crate::harness::GrpcWebStream<pb::ExplainTechniqueResponse> {
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

/// Sends one chat message, on [`recommend`]'s terms and for the same reason:
/// this suite is about what the coach says, not who may ask it.
pub(super) async fn chat(
    db: &TestDatabase,
    model: Arc<dyn ModelClient>,
    user: &str,
    history: Vec<pb::ChatTurn>,
    message: &str,
) -> crate::harness::GrpcWebStream<pb::ChatResponse> {
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
    )
    .await;
}

pub(super) async fn set_profile(
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
        })
        .collect();

    harness::record(db, user, records).await.into_ok();
}

pub(super) async fn record_bolt(db: &TestDatabase, user: &str, seconds: u32) {
    harness::bolt_score(db, user, seconds).await.into_ok();
}
