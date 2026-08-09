//! What Prometheus scrapes, and the middleware that fills it.
//!
//! Two kinds of number live here and they answer different questions. Request
//! metrics say whether the server is healthy; the census says whether the
//! product is working. Only the second is why this file exists — a box nobody
//! is paying for is up in exactly the same way as one everybody is.
//!
//! The exposition is served on its own listener (`config::metrics_port`, see
//! `metrics_router`), never on the public one. The middleware below still wraps
//! the public router, because what it counts is that router's traffic.

use std::sync::{Arc, OnceLock};
use std::time::Instant;

use axum::extract::{Request, State};
use axum::http::{StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use metrics::{counter, gauge, histogram};
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};

use crate::features::entitlement::service;
use crate::features::entitlement::types::SubscriptionTier;
use crate::state::AppState;

/// Latency buckets, in seconds.
///
/// Chosen around what this server actually does rather than from a template:
/// the gRPC calls the app makes on a screen open are single-digit milliseconds,
/// and the assistant's streaming turn is seconds. Both ends need resolution, so
/// the bounds are wide and the middle is coarse.
const LATENCY_BUCKETS: &[f64] = &[
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

/// The recorder, installed once per process.
///
/// A `OnceLock` rather than a call in `main`, because `build_app` is what
/// `tests/e2e` drives and a global recorder may only be installed once. Every
/// test in the suite therefore shares one recorder, which is harmless: nothing
/// asserts on a counter, and the alternative is a metrics stack that exists in
/// production and not in the tests that are supposed to be running production's
/// router.
///
/// `Option` inside the lock, rather than a `Result` returned from an installer
/// that could be called twice: `get_or_init` runs its closure exactly once even
/// under concurrency, which is what makes "already installed" unreachable rather
/// than merely unlikely. A failure is still not a panic — this crate's rule is
/// that nothing on a request path unwraps (see the `expect_used` note in
/// Cargo.toml), and a server that refuses to boot because its telemetry would
/// not start is a worse outage than one with no telemetry.
static HANDLE: OnceLock<Option<PrometheusHandle>> = OnceLock::new();

/// Installs the recorder if this process has not already.
///
/// Called from both routers rather than lazily on first scrape, because the
/// middleware's macros are silent no-ops until a recorder exists — so a lazy
/// install would drop every request made before Prometheus first asked. Calling
/// it twice is the ordinary case and costs nothing.
pub fn install() {
    let _ = handle();
}

fn handle() -> Option<&'static PrometheusHandle> {
    HANDLE
        .get_or_init(|| {
            PrometheusBuilder::new()
                .set_buckets(LATENCY_BUCKETS)
                .and_then(PrometheusBuilder::install_recorder)
                .inspect_err(|error| {
                    tracing::error!(%error, "metrics recorder unavailable; /metrics will not answer");
                })
                .ok()
        })
        .as_ref()
}

/// One counter and one histogram per request, across both protocols.
///
/// Sits outside the gRPC layers so a request refused by the throttle or by CORS
/// is still counted — those refusals are the ones worth seeing on a graph, and
/// a metric that only counts requests which got as far as a handler cannot show
/// them.
pub async fn record(request: Request, next: Next) -> Response {
    let path = route_label(request.uri().path());
    let started = Instant::now();
    let response = next.run(request).await;
    let status = response.status().as_u16().to_string();

    counter!("ond_requests_total", "route" => path, "status" => status).increment(1);
    histogram!("ond_request_duration_seconds", "route" => path)
        .record(started.elapsed().as_secs_f64());

    response
}

/// Collapses a request path to a bounded label.
///
/// Cardinality is the whole point. A label taken straight from the URI lets
/// anything that can reach this server mint a new time series per request, and
/// the paths worth naming are already a closed set: the JSON routes, and the
/// gRPC methods the contract defines. Everything else is one bucket, which is
/// also where a scanner's `/wp-login.php` lands.
///
/// The scrape is not in the set because it never reaches this middleware: it is
/// served by a different router on a different port.
fn route_label(path: &str) -> &'static str {
    match path {
        "/health" => "/health",
        "/about" => "/about",
        _ if path.starts_with("/ond.v1.") => "grpc",
        _ => "other",
    }
}

/// The exposition, with the census refreshed on the way out.
///
/// Queried per scrape rather than kept current by a background task: the count
/// is one sequential scan of a small table every fifteen seconds, and a task
/// would add a lifecycle, a failure mode nothing watches, and a window in which
/// the number is older than the scrape claiming to have just read it.
#[allow(
    clippy::cast_precision_loss,
    reason = "a population that exceeded f64's 53-bit mantissa would be 9 quadrillion rows; the gauge type is f64 and there is nothing to convert through"
)]
pub async fn render(State(state): State<Arc<AppState>>) -> Response {
    let Some(handle) = handle() else {
        // Already logged at install. A 503 rather than an empty 200, so a scrape
        // failure shows up as a target down instead of as a product with no
        // users.
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    match service::census(&state.pool).await {
        Ok(census) => {
            gauge!("ond_users_total").set(census.users as f64);
            gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Plus.as_metric_label())
                .set(census.plus as f64);
            gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Coach.as_metric_label())
                .set(census.coach as f64);
            gauge!("ond_gross_mrr_usd").set(census.gross_mrr_usd);
        }
        Err(error) => {
            // The boundary for this one: nothing above it will see the error, so
            // this is the only place it can be said. NaN rather than leaving the
            // last good reading in place, because a gauge that keeps answering a
            // number it can no longer verify is a dashboard that looks healthiest
            // exactly when the database has stopped answering.
            tracing::warn!(%error, "census unavailable; reporting the product gauges as unknown");
            gauge!("ond_users_total").set(f64::NAN);
            gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Plus.as_metric_label())
                .set(f64::NAN);
            gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Coach.as_metric_label())
                .set(f64::NAN);
            gauge!("ond_gross_mrr_usd").set(f64::NAN);
        }
    }

    (
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            "text/plain; version=0.0.4; charset=utf-8",
        )],
        handle.render(),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The label set has to stay closed, or a scanner sweeping paths mints a
    /// time series per request and the scrape grows without bound.
    #[test]
    fn unknown_paths_collapse_to_one_label() {
        assert_eq!(route_label("/wp-login.php"), "other");
        assert_eq!(route_label("/../../etc/passwd"), "other");
        assert_eq!(route_label("/ond.v1.JourneyService/GetJourney"), "grpc");
        assert_eq!(route_label("/health"), "/health");
    }
}
