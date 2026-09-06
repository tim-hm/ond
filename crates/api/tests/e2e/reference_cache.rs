//! Process-lifetime reference caches, through the production router. These use
//! disposable databases because the defining rule is what happens when the
//! seeded tables change underneath one `AppState`: a unit test over a stand-in
//! cannot prove that the derivation reached Postgres or that a later RPC
//! reused the value rather than deriving it again.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use axum::Router;
use tonic::Code;

use crate::harness::{GrpcWebResponse, LIST_USER_TECHNIQUES, TestDatabase, call_grpc_web_with};

const USER: &str = "9d4e3f2a-0000-4000-8000-000000000001";

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

async fn list_user_techniques(app: Router) -> GrpcWebResponse<pb::ListUserTechniquesResponse> {
    call_grpc_web_with(
        app,
        LIST_USER_TECHNIQUES,
        &pb::ListUserTechniquesRequest {},
        &[(USER_ID_HEADER, USER)],
    )
    .await
}
