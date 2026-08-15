//! The private Prometheus endpoint for the entitlement census.

use std::sync::Arc;

use axum::extract::State;
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use metrics::gauge;

use super::super::types::SubscriptionTier;
use crate::obs;
use crate::state::AppState;

/// Renders recorder output after refreshing the product gauges.
///
/// This handler owns the feature-specific query and labels; `obs::metrics`
/// owns only the process recorder. On refresh failure every gauge becomes NaN
/// immediately, so a scrape never presents an old population as current.
#[allow(
    clippy::cast_precision_loss,
    reason = "a population past f64's 53-bit mantissa is 9 quadrillion rows; Prometheus gauges are f64"
)]
pub async fn render(State(state): State<Arc<AppState>>) -> Response {
    if !obs::metrics::available() {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }

    let snapshot = state.census.get(&state.pool).await;
    if let Some(error) = snapshot.refresh_error {
        tracing::warn!(%error, "census unavailable; reporting the product gauges as unknown");
    }

    if let Some(census) = snapshot.census {
        gauge!("ond_users_total").set(census.users as f64);
        gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Plus.as_metric_label())
            .set(census.plus as f64);
        gauge!("ond_gross_mrr_usd").set(census.gross_mrr_usd);
    } else {
        gauge!("ond_users_total").set(f64::NAN);
        gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Plus.as_metric_label())
            .set(f64::NAN);
        gauge!("ond_gross_mrr_usd").set(f64::NAN);
    }

    (
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            "text/plain; version=0.0.4; charset=utf-8",
        )],
        obs::metrics::exposition().unwrap_or_default(),
    )
        .into_response()
}
