//! The public build and runtime identity endpoint.

use std::sync::Arc;

use axum::Json;
use axum::extract::State;
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
    /// The source revision baked into this binary.
    pub commit: &'static str,

    /// When this binary was built.
    pub built_at: &'static str,
}

#[derive(Serialize)]
pub(super) struct About {
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
    /// read.
    assistant: &'static str,
}

pub(super) async fn about(State(state): State<Arc<AppState>>) -> Json<About> {
    Json(About {
        build: BUILD_INFO,
        environment: state.config.environment.as_str(),
        assistant: state.assistant.mode().as_str(),
    })
}
