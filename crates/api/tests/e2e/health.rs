//! The JSON surface.

use std::sync::Arc;

use api::assistant::{DisabledModelClient, GuardedModelClient, ModelClient, ModelRequest};
use api::entitlement::AppStoreVerifier;
use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use tower::ServiceExt;

use crate::harness::{ScriptedIdentityVerifier, ScriptedModel, build_app, build_app_with};

/// `/health` is documented as liveness-only, and the reason is operational: a
/// health check that fails when Postgres is unreachable turns a recoverable
/// dependency outage into a restart loop of a process that was fine.
///
/// The pool here is lazy and points at a port nothing listens on, so the route
/// answering at all proves it issued no query. Adding one to `/health` later
/// fails here rather than in an incident.
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

    // A lazy pool keeps a connector task alive; without this nextest reports the
    // test as leaky because the process still holds it at exit.
    unreachable.close().await;
}

/// `/about` reports what calls did, not what is configured.
///
/// The failure this guards is the one that hid an unapplied IAM policy for a
/// day. A process that cannot invoke Bedrock boots clean, answers every RPC,
/// and answers all of them from the rules, leaving one `warn` in the logs on
/// the box as the only record — and the configuration naming Bedrock was
/// correct throughout, so any field derived from it would have read `live` for
/// the whole outage. Reading the mode here costs no model call and no
/// entitlement, which is the other half of the point: a real chat request needs
/// the Coach tier, and this question has to be answerable before anybody holds
/// one.
///
/// All three reachable states in one test, because each is only meaningful
/// against the others: a field stuck on `fallback` would look as trustworthy as
/// one stuck on `live`, and `untried` is the state that tells the two apart on a
/// deployment nobody has exercised yet.
#[tokio::test]
async fn about_reports_what_the_model_did_not_what_is_configured() {
    let pool = lazy_unreachable_pool();

    let about = |assistant: Arc<dyn ModelClient>| {
        build_app_with(
            pool.clone(),
            assistant,
            Arc::new(AppStoreVerifier),
            ScriptedIdentityVerifier::refusing(),
        )
    };

    assert_eq!(
        assistant_mode(about(Arc::new(DisabledModelClient))).await,
        "fallback",
        "no model behind the seam is what a machine that cannot sign for one boots into"
    );

    // Composed exactly as `install` composes production: the breaker is what
    // watches calls, so it is the only thing that can promote a mode to `live`.
    let guarded = Arc::new(GuardedModelClient::new(ScriptedModel::always(Ok(
        "a reply".to_owned(),
    ))));
    assert_eq!(
        assistant_mode(about(guarded.clone())).await,
        "untried",
        "a model that is installed and configured has still proven nothing"
    );

    guarded
        .complete(&ModelRequest {
            cacheable_prefix: String::new(),
            instruction: String::new(),
            turns: Vec::new(),
            tools: Vec::new(),
            max_tokens: 1,
        })
        .await
        .expect("the scripted model answers");
    assert_eq!(
        assistant_mode(about(guarded)).await,
        "live",
        "one successful call, and nothing else, is what earns `live`"
    );

    pool.close().await;
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

/// The `assistant` field of `/about`, as the string a `curl` would print.
async fn assistant_mode(app: Router) -> String {
    let response = app
        .oneshot(
            Request::get("/about")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");
    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("the response body is readable");
    let about: serde_json::Value = serde_json::from_slice(&body).expect("/about answers JSON");

    about["assistant"]
        .as_str()
        .expect("/about names the assistant's mode")
        .to_owned()
}
