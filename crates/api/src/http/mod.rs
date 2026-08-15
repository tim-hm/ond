//! The JSON/REST surface.
//!
//! `router()` is the single aggregation point for axum routes — every path this
//! server answers over plain HTTP is visible in one place. The domain API is
//! served over gRPC-Web; these routes exist for liveness checks and for
//! answering "what is actually deployed" with `curl`.

mod about;
mod health;

use std::sync::Arc;

use axum::Router;
use axum::routing::get;

use about::about;
pub use about::{BUILD_INFO, BuildInfo};
use health::health;

use crate::state::AppState;

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
