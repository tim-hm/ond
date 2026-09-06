//! The JSON surface.

use axum::body::{Body, to_bytes};
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use tower::ServiceExt;

use crate::harness::build_app;

/// `/health` is documented as liveness-only, and the reason is operational: a
/// health check that fails when Postgres is unreachable turns a recoverable
/// dependency outage into a restart loop of a process that was fine. The pool
/// here is lazy and points at a port nothing listens on, so the route
/// answering at all proves it issued no query.
#[tokio::test]
async fn health_answers_without_a_reachable_database() {
    let unreachable = lazy_unreachable_pool();

    let response = build_app(unreachable.clone())
        .oneshot(
            Request::get("/health")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");

    assert_eq!(response.status(), StatusCode::OK);

    // The exact bytes: infra/main.tf's Route 53 health check searches the
    // response for this literal, and the probe does not verify the certificate,
    // so the body is the only part that says who answered. Respacing the JSON
    // would leave the probe matching nothing and the box reported unhealthy from outside.
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("a readable body");
    assert_eq!(
        std::str::from_utf8(&body).expect("utf-8"),
        r#"{"status":"ok"}"#
    );

    // A lazy pool keeps a connector task alive; without this nextest reports the
    // test as leaky because the process still holds it at exit.
    unreachable.close().await;
}

/// A pool pointing at a port nothing listens on, connected lazily.
///
/// Both routes in this file are documented as touching no database, so the
/// suite proves it rather than asserting it — a query added to either one fails
/// here instead of in an incident.
fn lazy_unreachable_pool() -> PgPool {
    let options: PgConnectOptions = "postgres://nobody@127.0.0.1:1/nowhere"
        .parse()
        .expect("a valid connection string");
    PgPoolOptions::new().connect_lazy_with(options)
}

#[tokio::test]
async fn about_reports_the_build_without_a_model_provider() {
    let pool = lazy_unreachable_pool();
    let response = build_app(pool.clone())
        .oneshot(
            Request::get("/about")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");
    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("a readable body");
    let about: serde_json::Value = serde_json::from_slice(&body).expect("valid JSON");
    assert!(about["built_at"].is_string());
    assert_eq!(about["environment"], "dev");
    assert!(about.get("assistant").is_none());
    pool.close().await;
}

#[tokio::test]
async fn retired_model_endpoints_are_unimplemented() {
    use crate::harness::call_grpc_web;
    use api::proto::ond::v1 as pb;

    let pool = lazy_unreachable_pool();
    for path in [
        "/ond.v1.AssistantService/Chat",
        "/ond.v1.AssistantService/GetRecommendation",
    ] {
        let response = call_grpc_web::<_, pb::ListTechniquesResponse>(
            build_app(pool.clone()),
            path,
            &pb::ListTechniquesRequest {},
        )
        .await;
        assert_eq!(response.status, tonic::Code::Unimplemented as i32);
    }
    pool.close().await;
}
