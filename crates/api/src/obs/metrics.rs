//! Prometheus recorder mechanics and transport-wide request metrics. Product
//! gauges live with the feature that defines their meaning; this module owns
//! the process recorder and the two transport boundaries: ordinary HTTP at the
//! outer router, and native gRPC inside the gRPC-Web envelope where final
//! trailers remain observable.

use std::sync::OnceLock;
use std::time::{Duration, Instant};

use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::Response;
use metrics::{counter, gauge, histogram};
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};

use super::completion::{instrument_grpc_response, method_label, record_grpc_completion};

/// Latency buckets, in seconds, chosen around what this server actually does:
/// screen-open gRPC calls are single-digit milliseconds and the assistant's
/// streaming turn is seconds, so both ends need resolution — the bounds are
/// wide and the middle is coarse.
const LATENCY_BUCKETS: &[f64] = &[
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

/// The recorder, installed once per process. A `OnceLock` rather than a call
/// in `main`, because `build_app` is what `tests/e2e` drives and a global
/// recorder may only be installed once — every test shares one recorder.
/// `Option` inside the lock makes installation failure a degraded process
/// rather than a boot panic: logged once, and `/metrics` answers 503.
static HANDLE: OnceLock<Option<PrometheusHandle>> = OnceLock::new();

/// Installs the recorder if this process has not already.
///
/// Called from both routers rather than lazily on first scrape, because metrics
/// macros are silent no-ops until a recorder exists. Calling it twice is the
/// ordinary case and costs nothing.
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

/// Publishes what is running, as the conventional always-1 info series. In
/// Prometheus a step in this series is a deploy, so a latency regression can
/// be lined up against the release that caused it. One series, and it stays
/// one: the labels change value on a deploy, and the old series simply stops.
pub fn describe_build(commit: &'static str, built_at: &'static str, environment: &'static str) {
    gauge!(
        "ond_build_info",
        "commit" => commit,
        "built_at" => built_at,
        "environment" => environment
    )
    .set(1.0);
}

/// Publishes when this process started, as a unix timestamp — what the
/// dashboard's deploy annotation reads. `changes(ond_build_info[…])` looks
/// right and is not: that series is always 1 and a deploy changes its labels,
/// so `changes()` sees nothing. Process start genuinely moves on every deploy
/// (and crash-restart), and it answers uptime without a process collector.
pub fn describe_start_time() {
    let started = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0.0, |since| since.as_secs_f64());
    gauge!("ond_process_start_time_seconds").set(started);
}

/// Publishes the connection pool's occupancy, read at scrape time. Pool
/// exhaustion is the documented failure cliff, but the fast `PoolTimedOut`
/// says how the cliff was reached, never how close the edge is — these two
/// gauges are the approach. `size` counts connections that exist, idle or not,
/// so in-use is the difference; sqlx keeps both, so nothing here can drift.
#[allow(
    clippy::cast_precision_loss,
    reason = "num_idle is bounded by max_connections, which is forty"
)]
pub(crate) fn refresh_pool(pool: &sqlx::PgPool) {
    let size = f64::from(pool.size());
    let idle = pool.num_idle() as f64;

    gauge!("ond_db_pool_connections", "state" => "idle").set(idle);
    gauge!("ond_db_pool_connections", "state" => "in_use").set(size - idle);
}

/// Publishes the panic counter at zero, before anything has panicked — what
/// lets `ProcessPanicked` fire on the *first* panic. A counter that springs
/// into existence already reading 1 has no earlier sample, so `increase()` is
/// 0 for the whole window and the rule notices only the second panic. Separate
/// from `install_panic_hook` so the e2e suite's exposition carries the series too.
pub fn describe_panics() {
    counter!("ond_panics_total").increment(0);
}

/// Publishes the arrival counter at zero, for the reason `describe_panics`
/// gives: an unregistered counter is absent from the exposition entirely, so a
/// panel reading it says "No data" — which looks like a broken query, not
/// "nobody yet". The sign-in counter is the account feature's, registered beside it.
pub fn describe_identities() {
    counter!("ond_identities_created_total").increment(0);
}

/// Counts an identity seen for the first time. Transport-wide rather than a
/// feature's: the row is written by `identity::resolve` for any caller of any
/// RPC, and no feature owns the moment. A counter rather than a line — arrival
/// is a rate, and a line per arrival stops being readable exactly when the
/// answer starts being good news; `ond_users_total` is a flat once-a-minute gauge.
pub fn identity_created() {
    counter!("ond_identities_created_total").increment(1);
}

/// Installs the hook that makes a panicking handler visible: hyper's
/// per-connection unwind catches the panic, the process carries on, and the
/// only trace was the default hook's unstructured stderr write — uncounted and
/// unparseable in production. The default hook is called first, not replaced;
/// its output is the backtrace. `describe_panics` registers the counter, not this.
pub fn install_panic_hook() {
    let default = std::panic::take_hook();

    std::panic::set_hook(Box::new(move |info| {
        counter!("ond_panics_total").increment(1);
        // Location only, never the payload: a panic message can carry whatever
        // was being formatted when it fired, and this process handles other
        // people's data.
        let location = info
            .location()
            .map_or_else(|| "unknown".to_owned(), ToString::to_string);
        tracing::error!(location = %location, "a task panicked");
        default(info);
    }));
}

/// The recorder's current text exposition.
pub(crate) fn exposition() -> Option<String> {
    Some(handle()?.render())
}

/// Records JSON requests and failures that never reached native gRPC.
/// Installed outside CORS so it sees that boundary's failures as well as the
/// public routes. An HTTP-200 gRPC envelope is deliberately skipped:
/// [`record_grpc`] records that call once, with its final native status.
pub async fn record_http(request: Request, next: Next) -> Response {
    let route = route_label(request.uri().path());
    let started = Instant::now();
    let response = next.run(request).await;

    if let Some((route, status)) = http_outcome(route, response.status()) {
        record_completion(route, status, started.elapsed());
    }

    response
}

/// Records one native gRPC call when its final status becomes known. Installed
/// inside `GrpcWebLayer` and outside auth, throttle and the handlers. A
/// refusal in the response head is recorded immediately; unary and streaming
/// calls are wrapped so their terminal trailers decide the metric.
pub async fn record_grpc(request: Request, next: Next) -> Response {
    // Resolved before the handler runs, because the response has no path on it
    // and the completion callback outlives the request.
    let method = method_label(request.uri().path());
    let started = Instant::now();
    let response = next.run(request).await;

    instrument_grpc_response(response, started, move |code, elapsed| {
        record_grpc_completion(method, code, elapsed);
    })
}

/// Collapses a request path to a bounded label — a label taken straight from
/// the URI lets any caller mint a new time series per request. Scanner paths
/// become `other`; contract paths become `grpc`, so [`http_outcome`] can skip
/// a completed envelope or relabel a pre-envelope failure as `grpc_transport`.
fn route_label(path: &str) -> &'static str {
    match path {
        "/health" => "/health",
        "/about" => "/about",
        _ if path.starts_with("/ond.v1.") => "grpc",
        _ => "other",
    }
}

fn http_outcome(route: &'static str, status: StatusCode) -> Option<(&'static str, u16)> {
    if route == "grpc" && status == StatusCode::OK {
        return None;
    }
    if route == "grpc" {
        return Some(("grpc_transport", status.as_u16()));
    }
    Some((route, status.as_u16()))
}

fn record_completion(route: &'static str, status: u16, elapsed: Duration) {
    counter!(
        "ond_requests_total",
        "route" => route,
        "status" => status.to_string()
    )
    .increment(1);
    histogram!("ond_request_duration_seconds", "route" => route).record(elapsed.as_secs_f64());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_paths_collapse_to_one_label() {
        assert_eq!(route_label("/wp-login.php"), "other");
        assert_eq!(route_label("/../../etc/passwd"), "other");
        assert_eq!(route_label("/ond.v1.JourneyService/GetJourney"), "grpc");
        assert_eq!(route_label("/health"), "/health");
    }

    #[test]
    fn http_200_grpc_envelopes_are_not_double_counted() {
        assert_eq!(http_outcome("grpc", StatusCode::OK), None);
        assert_eq!(
            http_outcome("/health", StatusCode::OK),
            Some(("/health", 200))
        );
        assert_eq!(
            http_outcome("grpc", StatusCode::FORBIDDEN),
            Some(("grpc_transport", 403))
        );
    }
}
