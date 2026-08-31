//! Process-lifetime reference caches, through the production router. These use
//! disposable databases because the defining rule is what happens when the
//! seeded tables change underneath one `AppState`: a unit test over a stand-in
//! cannot prove that the derivation reached Postgres or that a later RPC
//! reused the value rather than deriving it again.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use axum::Router;
use tonic::Code;

use crate::harness::{
    GET_RECOMMENDATION, GrpcWebResponse, LIST_USER_TECHNIQUES, ScriptedModel, TestDatabase,
    call_grpc_web_with,
};

const USER: &str = "9d4e3f2a-0000-4000-8000-000000000001";

/// Once curated reference data has been derived, a later assistant request
/// must not return to tables a migration cannot have changed without restarting
/// the process.
#[tokio::test]
async fn the_curated_cache_reuses_its_successful_value() {
    let db = TestDatabase::create("curated_cache_reuse").await;
    db.given_subscriber(USER).await;
    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));
    let app = db.app_with_model(model.clone());

    recommend(app.clone()).await.into_ok();
    empty_catalogue(&db).await;
    recommend(app).await.into_ok();

    assert_eq!(model.calls(), 2, "both requests reached the model");
}

/// The empty answer possible before the seed transaction commits must leave the
/// cache retryable. Reseeding the same database then lets the same process
/// recover without rebuilding its router.
#[tokio::test]
async fn the_curated_cache_recovers_after_an_empty_first_derivation() {
    let db = TestDatabase::create("curated_cache_recovery").await;
    db.given_subscriber(USER).await;
    empty_catalogue(&db).await;
    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));
    let app = db.app_with_model(model.clone());

    let first = recommend(app.clone()).await;
    assert_eq!(first.status, Code::Internal as i32);
    assert_eq!(
        model.calls(),
        0,
        "an empty catalogue never reaches the model"
    );

    migrate::seed::run(&db.pool)
        .await
        .expect("the reference seed is restored");

    recommend(app).await.into_ok();
    assert_eq!(model.calls(), 1, "the retry uses the reseeded catalogue");
}

/// The authored-exercise limits are another process value. Emptying the source
/// rows after one response makes a second successful response proof that the
/// router reused the value already in memory.
#[tokio::test]
async fn the_phase_limits_cache_reuses_its_successful_value() {
    let db = TestDatabase::create("phase_cache_reuse").await;
    let app = db.app();

    let first = list_user_techniques(app.clone()).await.into_ok();
    assert!(
        first.limits.is_some(),
        "the initial derivation returns limits"
    );
    sqlx::query("TRUNCATE technique_phases")
        .execute(&db.pool)
        .await
        .expect("the seeded phase rows are cleared");
    let second = list_user_techniques(app).await.into_ok();

    assert_eq!(second.limits, first.limits);
}

/// `OnceCell::get_or_try_init` must not turn an unavailable source table into a
/// process-lifetime failure. Restoring the table makes the same router's next
/// call derive and retain the limits normally.
#[tokio::test]
async fn the_phase_limits_cache_recovers_after_an_initial_database_error() {
    let db = TestDatabase::create("phase_cache_recovery").await;
    let app = db.app();
    sqlx::query("ALTER TABLE technique_phases RENAME TO unavailable_technique_phases")
        .execute(&db.pool)
        .await
        .expect("the source table is made unavailable");

    let first = list_user_techniques(app.clone()).await;
    assert_eq!(first.status, Code::Internal as i32);

    sqlx::query("ALTER TABLE unavailable_technique_phases RENAME TO technique_phases")
        .execute(&db.pool)
        .await
        .expect("the source table is restored");

    let recovered = list_user_techniques(app).await.into_ok();
    assert!(recovered.limits.is_some());
}

async fn recommend(app: Router) -> GrpcWebResponse<pb::GetRecommendationResponse> {
    call_grpc_web_with(
        app,
        GET_RECOMMENDATION,
        &pb::GetRecommendationRequest {
            health_context: None,
        },
        &[(USER_ID_HEADER, USER)],
    )
    .await
}

async fn list_user_techniques(app: Router) -> GrpcWebResponse<pb::ListUserTechniquesResponse> {
    call_grpc_web_with(
        app,
        LIST_USER_TECHNIQUES,
        &pb::ListUserTechniquesRequest {},
        &[(USER_ID_HEADER, USER)],
    )
    .await
}

async fn empty_catalogue(db: &TestDatabase) {
    sqlx::query("TRUNCATE techniques CASCADE")
        .execute(&db.pool)
        .await
        .expect("the curated catalogue is cleared");
}
