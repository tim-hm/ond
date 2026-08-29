//! Reading the scrape target, for the suites that assert on what it says.
//! Shared rather than private to `metrics.rs` because the counters worth
//! asserting on belong to the features that move them — a refund's outcome is
//! an entitlement claim — while the target they are read from is one route.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

use super::TestDatabase;

/// The exposition this process would serve to Prometheus.
pub async fn scrape(database: &TestDatabase) -> String {
    let response = database
        .metrics_app()
        .oneshot(
            Request::get("/metrics")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("the exposition is readable");

    String::from_utf8(body.to_vec()).expect("the exposition is text")
}

/// Sums every series in `exposition` whose line starts with `prefix` — so a
/// counter's total is readable without naming labels the test does not care
/// about, and an untouched metric sums to zero. Read twice and subtracted,
/// never asserted against an absolute: the recorder is process-global, so the
/// value depends on what else ran. Counters only, which the integer return is what says.
pub fn counter_total(exposition: &str, prefix: &str) -> u64 {
    exposition
        .lines()
        .filter(|line| line.starts_with(prefix))
        .filter_map(|line| line.rsplit_once(' '))
        .filter_map(|(_, value)| value.parse::<u64>().ok())
        .sum()
}
