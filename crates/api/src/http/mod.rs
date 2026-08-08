//! The JSON/REST surface.
//!
//! `router()` is the single aggregation point for axum routes — every path this
//! server answers over plain HTTP is visible in one place. Feature handlers
//! belong under `features::*::handlers::http` and are imported here as leaf
//! functions rather than mounted as sub-routers, so no route can exist without
//! appearing in this file.
//!
//! The domain API itself is served over gRPC-Web, not from here (see
//! docs/transport.md). These routes exist for liveness checks and for answering
//! "what is actually deployed" with `curl`.

use std::sync::Arc;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::state::AppState;

/// Commit and build time, baked in by `build.rs`.
pub const BUILD_INFO: BuildInfo = BuildInfo {
    commit: env!("BUILD_GIT_COMMIT_HASH"),
    built_at: env!("BUILD_TIMESTAMP"),
};

/// Which build is answering, as `/about` reports it.
///
/// `&'static str` rather than owned strings because both fields are `env!`
/// values baked in by `build.rs` — there is nothing to read at runtime, nothing
/// to fail, and therefore one `const` [`BUILD_INFO`] rather than a lookup.
#[derive(Debug, Clone, Copy, Serialize)]
pub struct BuildInfo {
    pub commit: &'static str,
    pub built_at: &'static str,
}

/// The JSON routes, with their state already bound.
///
/// Returns a `Router` with no state parameter left open, which is what lets
/// `build_app` hang the gRPC fallback and the shared layers off it without
/// threading `AppState` through a second time.
pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/about", get(about))
        .with_state(state)
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
}

/// Liveness only — deliberately does not touch the database.
///
/// A health check that fails when Postgres is unreachable turns a recoverable
/// dependency outage into a restart loop of a process that was fine.
async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

#[derive(Serialize)]
struct About {
    #[serde(flatten)]
    build: BuildInfo,
    /// Which environment this process believes it is. Reported because
    /// `OND_ENV` decides the CORS policy and the log format, and "it is
    /// running the environment I think it is" is otherwise unverifiable from
    /// outside the process.
    environment: &'static str,

    /// Where the coach's replies are coming from — `live`, `untried`,
    /// `interrupted` or `fallback`, as `AssistantMode` defines them.
    ///
    /// Reported because the alternative is invisible. A deployment that cannot
    /// reach the model boots clean and answers every RPC from the rules, and
    /// the only record is one `warn` in the logs on the box. This makes the
    /// same fact a `curl`, and it costs no model call and no subscription to
    /// read — so the question can be asked before anyone holds the Coach tier a
    /// real chat request needs.
    assistant: &'static str,
}

async fn about(State(state): State<Arc<AppState>>) -> Json<About> {
    Json(About {
        build: BUILD_INFO,
        environment: state.config.environment.as_str(),
        assistant: state.assistant.mode().as_str(),
    })
}
