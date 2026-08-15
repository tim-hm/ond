//! What every assistant test builds its world out of: the streaming route, the
//! two identities, the scripted-model call helpers, and the
//! profile and practice rows the prompt is assembled from.
//!
//! Here rather than in each file, on `journey::fixtures`'s terms: all four
//! suites ask the same two RPCs, and four copies of `recommend()` would be
//! four places for a test's setup to drift.
//!
//! Everybody here is subscribed, and the upsert lives in the helpers rather
//! than in each test: the assistant is what önd+ sells, so a caller who has
//! bought nothing never reaches the model at all and every test about what the
//! coach *says* would be asserting against the refusal instead. Who may ask is
//! `entitlement.rs`'s question, and `chat_refuses_somebody_who_has_bought_nothing`
//! is the one test here that deliberately skips these helpers to pin it.

use std::sync::Arc;

use api::assistant::{ModelChunk, ModelClient, ModelError, ModelRequest, ModelStream};
use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;

use crate::harness::{self, TestDatabase, call_grpc_web_stream_with, call_grpc_web_with};

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

/// Asks for a recommendation as a subscriber.
///
/// The subscription is arranged here so no test in this suite has to say it:
/// what may reach the model is `entitlement.rs`'s question, and this suite is
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
                // Every profile these helpers write carries one, so the
                // boundary test can pin that it reaches the instruction and
                // not the shared prefix without a second setup path.
                given_name: "Tomas".to_owned(),
                ..pb::Profile::default()
            }),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await;

    response.into_ok();
}

/// Saves one exercise of this person's own through the real
/// `UserTechniqueService`, so what the coach is briefed on is what the composer
/// actually writes.
///
/// A slow exhale, which is the shape the authoring limits are most permissive
/// about — this exists to put a *name* in the prompt, and a draft rejected for
/// its pattern would fail the test for the wrong reason.
pub(super) async fn save_exercise(db: &TestDatabase, user: &str, name: &str) {
    let response: crate::harness::GrpcWebResponse<pb::CreateUserTechniqueResponse> =
        call_grpc_web_with(
            db.app(),
            "/ond.v1.UserTechniqueService/CreateUserTechnique",
            &pb::CreateUserTechniqueRequest {
                draft: Some(pb::TechniqueDraft {
                    name: name.to_owned(),
                    summary: String::new(),
                    goal: pb::TechniqueGoal::Sleep as i32,
                    stages: vec![pb::DraftStage {
                        cycles: 10,
                        phases: vec![
                            pb::DraftPhase {
                                duration_ms: 4000,
                                movement: Some(pb::draft_phase::Movement::Inhale(
                                    pb::Passage::Nose as i32,
                                )),
                            },
                            pb::DraftPhase {
                                duration_ms: 8000,
                                movement: Some(pb::draft_phase::Movement::Exhale(
                                    pb::Passage::Nose as i32,
                                )),
                            },
                        ],
                    }],
                    rounds: 1,
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
            occasion_slug: None,
            surface: pb::DeliverySurface::Unspecified as i32,
        })
        .collect();

    harness::record(db, user, records).await.into_ok();
}

pub(super) async fn record_bolt(db: &TestDatabase, user: &str, seconds: u32) {
    harness::bolt_score(db, user, seconds).await.into_ok();
}
