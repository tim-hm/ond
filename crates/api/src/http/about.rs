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

/// Which build is answering, as the metrics listener labels `ond_build_info`.
///
/// `&'static str` rather than owned strings because both fields are `env!`
/// values baked in by `build.rs` — there is nothing to read at runtime, nothing
/// to fail, and therefore one `const` [`BUILD_INFO`] rather than a lookup.
#[derive(Debug, Clone, Copy)]
pub struct BuildInfo {
    /// The source revision baked into this binary. Never in a public body: the
    /// listener carrying it is private by construction.
    pub commit: &'static str,

    /// When this binary was built.
    pub built_at: &'static str,
}

/// What `/about` answers. Caddy proxies every path on the API host, so this
/// body is public and unrationed — and it names no source revision. The commit
/// is published on the metrics listener instead, as a label of
/// `ond_build_info`, which no rule of Caddy's can expose.
#[derive(Serialize)]
pub(super) struct About {
    /// When this binary was built. Enough to answer "did my deploy land"
    /// without naming the revision it landed.
    built_at: &'static str,

    /// Which environment this process believes it is. Reported because
    /// `OND_ENV` decides the CORS policy and the log format, and "it is
    /// running the environment I think it is" is otherwise unverifiable from
    /// outside the process.
    environment: &'static str,

    /// Where the coach's replies are coming from — `live`, `untried`,
    /// `interrupted` or `fallback`, as `AssistantMode` defines them. Reported
    /// because the alternative is invisible: a deployment that cannot reach
    /// the model boots clean and answers every RPC from the rules, with one
    /// `warn` in the logs as the only record. This makes the same fact a `curl`.
    assistant: &'static str,
}

pub(super) async fn about(State(state): State<Arc<AppState>>) -> Json<About> {
    Json(About {
        built_at: BUILD_INFO.built_at,
        environment: state.config.environment.as_str(),
        assistant: state.assistant.mode().as_str(),
    })
}
