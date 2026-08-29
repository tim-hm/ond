//! Shared domain arrangements and RPC helpers.

use api::assistant::daily_model_calls;
use api::entitlement::Tier;
use api::identity::{SESSION_CREDENTIAL_HEADER, USER_ID_HEADER};
use api::proto::ond::v1 as pb;
use axum::Router;
use chrono::{DateTime, Utc};
use ring::digest::{SHA256, digest};
use sqlx::PgPool;

use super::{GrpcWebResponse, SCRIPTED_NONCE_SEPARATOR, TestDatabase, call_grpc_web_with};

/// One person's daily model allowance.
pub fn allowance(tier: Tier) -> usize {
    daily_model_calls(tier).map_or(0, |calls| {
        usize::try_from(calls).expect("an allowance is never negative")
    })
}

/// A user row, as the identity layer would have created it on the device's
/// first RPC. Written directly rather than by making a call, so a test can lay
/// out a population before any of them has made one. In the harness because
/// three suites want it and three hand-written `INSERT INTO users` would be
/// three places to update when the row grows a `NOT NULL`.
pub async fn given_user(pool: &PgPool, user: &str, display_name: &str) {
    sqlx::query(
        "INSERT INTO users (id, display_name) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name",
    )
    .bind(user.parse::<uuid::Uuid>().expect("a valid uuid"))
    .bind(display_name)
    .execute(pool)
    .await
    .expect("the user row is written");
}

/// Puts somebody on a paid tier by writing the columns `EntitlementService`
/// writes — straight into the row, for the suites that want a subscriber
/// without caring how they became one. The column names are a raw string here,
/// so a schema move that renames one is a runtime failure rather than a
/// compile error, and it should only be able to happen in one place.
pub async fn subscribe(pool: &PgPool, user: &str, tier: &str) {
    sqlx::query(
        "INSERT INTO users (id, subscription_tier, subscription_until)
         VALUES ($1, $2::subscription_tier, now() + interval '1 year')
         ON CONFLICT (id) DO UPDATE SET
           subscription_tier = EXCLUDED.subscription_tier,
           subscription_until = EXCLUDED.subscription_until",
    )
    .bind(user.parse::<uuid::Uuid>().expect("a valid uuid"))
    .bind(tier)
    .execute(pool)
    .await
    .expect("the subscription is written");
}

/// The headers one caller sends, with a credential when they have one.
///
/// A `Vec` rather than a fixed array because the anonymous case is one header
/// and the signed-in case is two, and every call site takes the slice.
pub fn headers<'a>(caller: &'a str, credential: Option<&'a str>) -> Vec<(&'a str, &'a str)> {
    let mut headers = vec![(USER_ID_HEADER, caller)];
    if let Some(credential) = credential {
        headers.push((SESSION_CREDENTIAL_HEADER, credential));
    }
    headers
}

/// Public for [`GET_RECOMMENDATION`]'s reason: `account.rs` drives this RPC for
/// what a sign-in does and `identity.rs` for what its credential buys, and one
/// definition keeps the path from being right in one suite and stale in the
/// other.
pub const SIGN_IN: &str = "/ond.v1.AccountService/SignInWithApple";
pub const BEGIN_APPLE_AUTHORIZATION: &str = "/ond.v1.AccountService/BeginAppleAuthorization";

/// Apple's `sub`, in the shape Apple actually issues one — the account both
/// sign-in suites script their verifier tokens onto.
pub const APPLE_ACCOUNT: &str = "001234.abcdef0123456789abcdef0123456789.0123";
pub const OTHER_APPLE_ACCOUNT: &str = "009876.fedcba9876543210fedcba9876543210.9876";

/// What a device holds after signing in: the identity it should carry from now
/// on, and the credential that proves it. The credential is not optional:
/// `identity::resolve` refuses a bound id that cannot prove itself on every
/// RPC, so a test that signs in and then calls anything else has to carry
/// both, exactly as the client does.
pub struct SignedIn {
    pub user_id: String,
    pub credential: String,
}

/// Starts the server ceremony and returns its raw nonce.
pub async fn begin_apple_authorization(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    purpose: pb::AppleAuthorizationPurpose,
) -> GrpcWebResponse<pb::BeginAppleAuthorizationResponse> {
    call_grpc_web_with(
        app,
        BEGIN_APPLE_AUTHORIZATION,
        &pb::BeginAppleAuthorizationRequest {
            purpose: purpose as i32,
        },
        &headers(caller, credential),
    )
    .await
}

/// Gives the scripted verifier the exact nonce claim Apple would sign after a
/// client SHA-256 hashes the raw challenge.
pub fn token_with_nonce(token: &str, raw_nonce: &str) -> String {
    let nonce = digest(&SHA256, raw_nonce.as_bytes());
    let mut claim = String::with_capacity(nonce.as_ref().len() * 2);
    for byte in nonce.as_ref() {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        claim.push(char::from(HEX[usize::from(byte >> 4)]));
        claim.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }

    format!("{token}{SCRIPTED_NONCE_SEPARATOR}{claim}")
}

/// A sign-in call whose signed nonce the caller controls.
pub async fn try_sign_in_with_nonce(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    token: &str,
    raw_nonce: &str,
) -> GrpcWebResponse<pb::SignInWithAppleResponse> {
    let request = pb::SignInWithAppleRequest {
        identity_token: token_with_nonce(token, raw_nonce),
    };

    call_grpc_web_with(app, SIGN_IN, &request, &headers(caller, credential)).await
}

/// The raw sign-in call, for the suites that assert on refusals — and the
/// credential a caller already bound must present to make the attempt at all.
pub async fn try_sign_in(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    token: &str,
) -> GrpcWebResponse<pb::SignInWithAppleResponse> {
    let challenge = begin_apple_authorization(
        app.clone(),
        caller,
        credential,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await;
    if challenge.status != tonic::Code::Ok as i32 {
        return GrpcWebResponse {
            message: None,
            status: challenge.status,
            status_message: challenge.status_message,
        };
    }
    let challenge = challenge.into_ok();

    try_sign_in_with_nonce(app, caller, credential, token, &challenge.nonce).await
}

/// A first sign-in from a device that has nothing to prove yet. Through the
/// wire rather than by writing the two rows directly, because the value under
/// test is the one a client would actually be holding — a fixture that minted
/// its own would pass whether or not `SignInWithApple` returned anything at all.
pub async fn sign_in(app: Router, caller: &str, token: &str) -> SignedIn {
    let response = try_sign_in(app, caller, None, token).await.into_ok();

    SignedIn {
        user_id: response.user_id,
        credential: response.session_credential,
    }
}

/// How many live session credentials an identity holds.
///
/// Counted in the database because the wire cannot answer it: after an erasure
/// the row is gone, so nothing an RPC could be asked would notice a
/// `user_sessions` row left behind pointing at nobody.
pub async fn live_credentials(pool: &PgPool, user: &str) -> i64 {
    sqlx::query_scalar!(
        r#"SELECT count(*) AS "count!" FROM user_sessions WHERE user_id = $1"#,
        user.parse::<uuid::Uuid>().expect("a valid uuid")
    )
    .fetch_one(pool)
    .await
    .expect("the credentials are countable")
}

/// Public for [`SIGN_IN`]'s reason: the `user_technique` suite drives this RPC
/// for what authoring does, the assistant's for the exercises its prompt is
/// briefed on, and one definition keeps the path from being right in one suite
/// and stale in the other.
pub const CREATE_USER_TECHNIQUE: &str = "/ond.v1.UserTechniqueService/CreateUserTechnique";

const RECORD_SESSIONS: &str = "/ond.v1.JourneyService/RecordSessions";
const RECORD_BOLT_SCORE: &str = "/ond.v1.JourneyService/RecordBoltScore";
const RECORD_RESTING_RATE: &str = "/ond.v1.JourneyService/RecordRestingRate";

/// Records sessions through the real `JourneyService`.
///
/// In the harness because two features' suites drive the RPC: the journey
/// suites for what recording does, the assistant's for the practice rows its
/// prompt is assembled from.
pub async fn record(
    db: &TestDatabase,
    user: &str,
    sessions: Vec<pb::SessionRecord>,
) -> GrpcWebResponse<pb::RecordSessionsResponse> {
    call_grpc_web_with(
        db.app(),
        RECORD_SESSIONS,
        &pb::RecordSessionsRequest { sessions },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

/// Saves one exercise of somebody's own through the real
/// `UserTechniqueService`, named by the caller. In the harness because two
/// suites drive this RPC. A slow nasal exhale, the shape the authoring limits
/// are most permissive about — every caller here wants a technique that
/// exists, so a draft refused for its pattern would fail for the wrong reason.
pub async fn save_technique(
    db: &TestDatabase,
    user: &str,
    name: &str,
) -> GrpcWebResponse<pb::CreateUserTechniqueResponse> {
    call_grpc_web_with(
        db.app(),
        CREATE_USER_TECHNIQUE,
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
    .await
}

/// Derives the score id from the measurement, so it is stable across runs and a
/// failing test leaves a row someone can go and look at. Distinct scores get
/// distinct ids, which is all most callers need; [`bolt_with`] is for the ones
/// that deliberately resend an id or place a measurement in time.
pub async fn bolt_score(
    db: &TestDatabase,
    user: &str,
    seconds: u32,
) -> GrpcWebResponse<pb::RecordBoltScoreResponse> {
    bolt_with(
        db,
        user,
        &format!("aaaaaaaa-0000-4000-8000-{seconds:012}"),
        seconds,
        None,
    )
    .await
}

pub async fn bolt_with(
    db: &TestDatabase,
    user: &str,
    client_score_id: &str,
    seconds: u32,
    measured_at: Option<DateTime<Utc>>,
) -> GrpcWebResponse<pb::RecordBoltScoreResponse> {
    call_grpc_web_with(
        db.app(),
        RECORD_BOLT_SCORE,
        &pb::RecordBoltScoreRequest {
            client_score_id: client_score_id.to_owned(),
            seconds,
            measured_at: measured_at.map(prost_timestamp),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

/// Derives the measurement id from the rate, on [`bolt_score`]'s terms and for
/// its reasons; [`resting_rate_with`] is for the callers that deliberately
/// resend an id or place a measurement in time.
pub async fn resting_rate(
    db: &TestDatabase,
    user: &str,
    breaths_per_minute: u32,
) -> GrpcWebResponse<pb::RecordRestingRateResponse> {
    resting_rate_with(
        db,
        user,
        &format!("bbbbbbbb-0000-4000-8000-{breaths_per_minute:012}"),
        breaths_per_minute,
        None,
    )
    .await
}

pub async fn resting_rate_with(
    db: &TestDatabase,
    user: &str,
    client_measurement_id: &str,
    breaths_per_minute: u32,
    measured_at: Option<DateTime<Utc>>,
) -> GrpcWebResponse<pb::RecordRestingRateResponse> {
    call_grpc_web_with(
        db.app(),
        RECORD_RESTING_RATE,
        &pb::RecordRestingRateRequest {
            client_measurement_id: client_measurement_id.to_owned(),
            breaths_per_minute,
            measured_at: measured_at.map(prost_timestamp),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub fn prost_timestamp(instant: DateTime<Utc>) -> prost_types::Timestamp {
    prost_types::Timestamp {
        seconds: instant.timestamp(),
        nanos: 0,
    }
}

pub fn hours_ago(hours: i64) -> DateTime<Utc> {
    Utc::now() - chrono::Duration::hours(hours)
}

/// Public because `assistant.rs` also drives this path anonymously, which
/// [`recommend`] cannot do — it always sends an identity and asserts success.
/// One definition either way, so the path cannot be right in one suite and
/// stale in the other.
pub const GET_RECOMMENDATION: &str = "/ond.v1.AssistantService/GetRecommendation";

/// Asks `GetRecommendation` over the wire, on a router the caller has built.
/// Two suites drive this RPC for opposite reasons, so only the call itself is
/// shared; taking an assembled `Router` keeps the subscription `assistant.rs`
/// wants and `entitlement.rs` must not have with the suite that wants it. One
/// construction site for the request, so a new field lands here, not in two places.
pub async fn recommend(
    app: Router,
    user: &str,
    health: Option<pb::HealthContext>,
) -> pb::GetRecommendationResponse {
    recommend_as(app, user, None, health).await
}

/// [`recommend`], for a caller who has to prove the identity they are
/// claiming. `credential` is `Some` only for a row bound to an Apple account,
/// which `identity::resolve` refuses without one. Paired with [`recommend`]
/// rather than folded into it: every caller in the assistant suite is
/// anonymous, and twenty tests should not carry a `None` to say so.
pub async fn recommend_as(
    app: Router,
    user: &str,
    credential: Option<&str>,
    health: Option<pb::HealthContext>,
) -> pb::GetRecommendationResponse {
    call_grpc_web_with::<_, pb::GetRecommendationResponse>(
        app,
        GET_RECOMMENDATION,
        &pb::GetRecommendationRequest {
            health_context: health,
        },
        &headers(user, credential),
    )
    .await
    .into_ok()
}
