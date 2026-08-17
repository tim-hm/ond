//! Reading the scrape target, for the suites that assert on what it says.
//!
//! Shared rather than private to `metrics.rs` because the counters worth
//! asserting on belong to the features that move them — a refund's outcome is an
//! entitlement claim — while the target they are read from is one route on one
//! router.

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

/// Sums every series in `exposition` whose line starts with `prefix`.
///
/// A prefix rather than an exact series, so a counter's total can be read without
/// naming labels the test does not care about — and so a family can be summed
/// across them. `# HELP` and `# TYPE` lines cannot match, and a metric no test has
/// touched sums to zero, which is the right reading of "nothing has incremented
/// it".
///
/// Read twice and subtracted, never asserted against an absolute. The recorder is
/// process-global and every test in this binary shares it, so a counter's value
/// depends on what else ran; the delta across one action does not.
///
/// Counters only, and the integer return is what says so: the exposition renders
/// one as a whole number, and a fractional value belongs to a gauge — which is
/// read by exact series rather than summed across a family.
pub fn counter_total(exposition: &str, prefix: &str) -> u64 {
    exposition
        .lines()
        .filter(|line| line.starts_with(prefix))
        .filter_map(|line| line.rsplit_once(' '))
        .filter_map(|(_, value)| value.parse::<u64>().ok())
        .sum()
}
