//! The scrape endpoint, and the one place that knows which gauges a scrape must
//! refresh first.
//!
//! Counters and histograms record themselves as things happen. Gauges cannot:
//! a population, a pool's occupancy and the provider's current mode are all
//! answers to "right now", and the only moment that has a right now is the
//! scrape. So this handler asks each owner to refresh, then renders.
//!
//! It imports features, which `obs::metrics` deliberately does not. That split
//! is the point: recorder mechanics stay free of anything domain-shaped, and the
//! composition sits in a module whose whole job is composition — the same shape
//! `grpc.rs` has, where one file names every feature so no feature has to name
//! another. Before this, the census handler lived inside `entitlement` and
//! rendered the entire exposition, which worked while entitlement was the only
//! feature with a gauge and made every later one a reason to import a second
//! feature into the first.

use std::sync::Arc;

use axum::extract::State;
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};

use crate::features::{assistant, entitlement};
use crate::obs::metrics;
use crate::state::AppState;

/// Refreshes every scrape-time gauge, then renders the recorder's exposition.
pub async fn render(State(state): State<Arc<AppState>>) -> Response {
    // The census is the only one that touches the database, and the only one
    // that can be slow. It is also single-flight cached for a minute, so four
    // ordinary scrapes share one scan, and it bounds its own wait so a stalled
    // query costs this gauge rather than the whole exposition.
    entitlement::metrics::refresh(&state.census, &state.pool).await;
    assistant::metrics::set_mode(state.assistant.mode());
    metrics::refresh_pool(&state.pool);

    let Some(body) = metrics::exposition() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    (
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            "text/plain; version=0.0.4; charset=utf-8",
        )],
        body,
    )
        .into_response()
}
