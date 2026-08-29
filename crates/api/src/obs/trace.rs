//! The subscriber chosen at boot and the one record every request leaves behind.

use std::time::Duration;

use axum::body::Body;
use axum::http::{HeaderMap, Request, Response};
use axum::middleware::Next;
use tower_http::classify::{ServerErrorsAsFailures, SharedClassifier};
use tower_http::trace::{MakeSpan, OnResponse, TraceLayer};
use tracing::{Span, field};
use tracing_subscriber::EnvFilter;

use crate::identity::UserId;

/// The filter every process runs under unless `RUST_LOG` overrides it. A
/// constant because the level it grants `api` decides whether a deployed
/// process is observable at all: a span below the filter is never created, so
/// anything that would have attached to the request span is lost before it
/// exists. The tests below run against this exact string for that reason.
pub const DEFAULT_FILTER: &str = "api=info,tower_http=info,warn";

/// Where gRPC puts an outcome known when the response head is written.
const GRPC_STATUS: &str = "grpc-status";

/// The paths a monitor asks about on a timer, so the only ones whose *success*
/// is not worth a line — Route 53 and Prometheus produce on the order of two
/// thousand identical `status=200` records an hour. Exact matches, never
/// prefixes: `/healthz` and `/health/` are somebody else asking, and the point
/// is to quieten the two callers that were asked to call.
const PROBE_PATHS: [&str; 2] = ["/health", "/metrics"];

/// The target the demoted record carries, so re-seeing probe traffic during an
/// incident is `RUST_LOG=api=info,api::probe=debug` rather than `api=debug`.
/// [`DEFAULT_FILTER`] needs no entry for it: `EnvFilter` matches by `::`
/// segment, so `api=info` already covers — and therefore drops — this one.
const PROBE_TARGET: &str = "api::probe";

fn is_probe(path: &str) -> bool {
    PROBE_PATHS.contains(&path)
}

/// Installs the global subscriber, and returns the filter it installed so the
/// boot line can carry it. A malformed `RUST_LOG` falls back to
/// [`DEFAULT_FILTER`] rather than failing the boot, silently by necessity —
/// there is no subscriber to report it through yet; naming the filter in force
/// on the next line is what makes the fallback visible.
pub fn init(json: bool) -> String {
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(DEFAULT_FILTER));
    let installed = filter.to_string();

    let builder = tracing_subscriber::fmt().with_env_filter(filter);

    if json {
        builder.json().init();
    } else {
        builder.init();
    }

    installed
}

/// The layer that produces the process's only per-request output. Every stock
/// `TraceLayer` callback is replaced: tower-http's `DEBUG` message level sits
/// under [`DEFAULT_FILTER`], which removed the span as well as the events; and
/// `new_for_http`'s classifier reads the HTTP status, while a failed RPC is
/// HTTP 200 with its code out of band — [`RequestComplete`] records the head status instead.
pub fn trace_layer() -> TraceLayer<
    SharedClassifier<ServerErrorsAsFailures>,
    RequestSpan,
    (),
    RequestComplete,
    (),
    (),
    (),
> {
    TraceLayer::new_for_http()
        .make_span_with(RequestSpan)
        .on_request(())
        .on_response(RequestComplete)
        .on_body_chunk(())
        .on_eos(())
        .on_failure(())
}

/// What [`mark_probes`] stamps and [`RequestComplete`] reads.
///
/// A response extension because `OnResponse` is handed the response and nothing
/// else — not the request, and not the path — while a `tracing` level is fixed
/// at its call site. The decision therefore has to travel *with* the response.
#[derive(Clone, Copy, Debug)]
struct Probe;

/// Marks a monitor's response, so the layer above can choose its level.
/// Installed immediately beneath [`trace_layer`] and nowhere else — a layer
/// between the two could rebuild the response and drop the marker, and the
/// failure would be silent: the noise simply comes back. The tests below fail
/// if the marker stops arriving.
pub async fn mark_probes(request: Request<Body>, next: Next) -> Response<Body> {
    // Read before the request moves into the inner service.
    let probe = is_probe(request.uri().path());
    let mut response = next.run(request).await;

    if probe {
        response.extensions_mut().insert(Probe);
    }

    response
}

/// The span every request runs inside, and the reason the `errors.rs`
/// conversions need no context of their own. `path` answers "which operation"
/// for both protocols; `user_id` is declared empty and filled by
/// [`record_user_id`] once `identity::resolve` knows who is calling — as
/// `identity::SupportReference`, never the id itself.
#[derive(Clone, Copy, Debug)]
pub struct RequestSpan;

impl<B> MakeSpan<B> for RequestSpan {
    fn make_span(&mut self, request: &Request<B>) -> Span {
        tracing::info_span!(
            "request",
            method = %request.method(),
            path = %request.uri().path(),
            user_id = field::Empty,
        )
    }
}

/// The one line a response head writes. `info` for every outcome: a fault is
/// already logged at `error` by the feature's `From<…> for Status`, and
/// restating it would double every error count taken off the log. A monitor's
/// successful probe drops to `debug` on [`PROBE_TARGET`] — one record either
/// way, only the level moves. `duration_ms` measures to the response head, not the last byte.
#[derive(Clone, Copy, Debug)]
pub struct RequestComplete;

impl<B> OnResponse<B> for RequestComplete {
    fn on_response(self, response: &Response<B>, latency: Duration, _span: &Span) {
        // Narrowed from the `u128` `as_millis` returns, because the JSON
        // formatter writes a `u128` as a *string* — a latency no aggregator can
        // aggregate. Nothing saturates: the ceiling is 584 million years.
        let duration_ms = u64::try_from(latency.as_millis()).unwrap_or(u64::MAX);
        let grpc_status = grpc_status(response.headers());
        let status = response.status();

        // Both halves of the rule meet here on purpose. The layer below says only
        // which paths a monitor asks about; the status half stays beside the level
        // it decides, so a `/health` that starts answering 503 — or a scrape the
        // timeout layer gives up on — is loud without anyone having to remember
        // to make it so.
        let quiet = response.extensions().get::<Probe>().is_some() && status.is_success();
        let status = status.as_u16();

        if quiet {
            tracing::debug!(
                target: PROBE_TARGET,
                status,
                grpc_status,
                duration_ms,
                "request completed"
            );
        } else {
            tracing::info!(status, grpc_status, duration_ms, "request completed");
        }
    }
}

/// Records the caller on the in-flight request span. Declared by
/// [`RequestSpan`] and filled in here so the two halves sit in one edit
/// radius: `Span::record` against a field the span never declared is a silent
/// no-op. What is recorded is `UserId::support_reference`, never the id itself
/// — that type carries the reasoning, and the rule.
pub fn record_user_id(user_id: UserId) {
    Span::current().record("user_id", field::display(user_id.support_reference()));
}

/// Reads the gRPC outcome a response head carries, if any. `GrpcWebLayer` has
/// folded genuine trailers into the body by the time this outer layer runs;
/// [`super::metrics::record_grpc`] observes the terminal status for counting.
/// The number rather than a `tonic::Code`, because the field exists to be
/// counted and grouped by.
fn grpc_status(headers: &HeaderMap) -> Option<i32> {
    headers.get(GRPC_STATUS)?.to_str().ok()?.parse().ok()
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::io;
    use std::sync::{Arc, Mutex};

    use axum::body::Body;
    use axum::http::{HeaderValue, StatusCode};
    use tower::{ServiceBuilder, ServiceExt};
    use tracing_subscriber::fmt::MakeWriter;
    use uuid::Uuid;

    use super::*;

    /// Collects formatted output so a test can assert on what a deployed
    /// process would have written, rather than on the shape of the layer.
    #[derive(Clone, Default)]
    struct Captured(Arc<Mutex<Vec<u8>>>);

    impl Captured {
        fn contents(&self) -> String {
            let bytes = self.0.lock().unwrap().clone();
            String::from_utf8(bytes).unwrap()
        }
    }

    impl io::Write for Captured {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    impl<'a> MakeWriter<'a> for Captured {
        type Writer = Self;

        fn make_writer(&'a self) -> Self::Writer {
            self.clone()
        }
    }

    /// Drives one request through [`trace_layer`] under [`DEFAULT_FILTER`] and
    /// returns what was logged. The filter is the production one rather than
    /// `TRACE` because the defect this layer fixes was an interaction between
    /// the callbacks' level and the filter — a lowered filter would have
    /// passed against the broken code.
    async fn log_of(
        path: &'static str,
        status: StatusCode,
        grpc_status: Option<&'static str>,
        user_id: Option<UserId>,
    ) -> String {
        log_of_under(DEFAULT_FILTER, path, status, grpc_status, user_id).await
    }

    /// [`log_of`], with the filter named — for the one case that has to prove
    /// a record still exists at a level the default drops. `mark_probes` is
    /// stacked under the trace layer in the same order `build_app` stacks
    /// them, because the marker crossing that boundary is part of what these tests assert.
    async fn log_of_under(
        filter: &str,
        path: &'static str,
        status: StatusCode,
        grpc_status: Option<&'static str>,
        user_id: Option<UserId>,
    ) -> String {
        let captured = Captured::default();
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter(EnvFilter::new(filter))
            .with_writer(captured.clone())
            .with_ansi(false)
            .finish();

        let service = ServiceBuilder::new()
            .layer(trace_layer())
            .layer(axum::middleware::from_fn(mark_probes))
            .service(tower::service_fn(
                move |_request: Request<Body>| async move {
                    if let Some(user_id) = user_id {
                        record_user_id(user_id);
                    }

                    let mut response = Response::new(Body::empty());
                    *response.status_mut() = status;
                    if let Some(code) = grpc_status {
                        response
                            .headers_mut()
                            .insert(GRPC_STATUS, HeaderValue::from_static(code));
                    }
                    Ok::<_, Infallible>(response)
                },
            ));

        let request = Request::post(path).body(Body::empty()).unwrap();

        let _guard = tracing::subscriber::set_default(subscriber);
        service.oneshot(request).await.unwrap();

        captured.contents()
    }

    /// The RPC path the records-a-caller tests below drive, and deliberately not
    /// a probe path.
    const RPC: &str = "/ond.v1.JourneyService/RecordSessions";

    /// One caller, whose whole id is `019238ab-cdef-4567-89ab-cdef01234567` and
    /// whose reference is the first two groups of it.
    fn caller() -> UserId {
        UserId(Uuid::from_u128(0x0192_38ab_cdef_4567_89ab_cdef_0123_4567))
    }

    /// The headline of [OBS-001] and [OBS-002] together: one failing RPC, and
    /// every field somebody answering "which user, which call, at what time"
    /// needs is on the line.
    #[tokio::test]
    async fn a_failed_rpc_names_its_caller_and_its_operation() {
        let logged = log_of(RPC, StatusCode::OK, Some("13"), Some(caller())).await;

        assert!(logged.contains("method=POST"), "{logged}");
        assert!(
            logged.contains("path=/ond.v1.JourneyService/RecordSessions"),
            "{logged}"
        );
        assert!(logged.contains("user_id=019238ab-cdef"), "{logged}");
        assert!(logged.contains("status=200"), "{logged}");
        assert!(logged.contains("grpc_status=13"), "{logged}");
        assert!(logged.contains("duration_ms="), "{logged}");
    }

    /// The credential does not reach the log stream ([SEC-006]): possession of
    /// the id is possession of the account, so writing it on every request
    /// line turns the logs into a list of account keys. The reference still
    /// answers "which caller", the only thing the field was ever asked for.
    #[tokio::test]
    async fn a_request_record_never_carries_the_whole_credential() {
        let caller = caller();
        let logged = log_of(RPC, StatusCode::OK, None, Some(caller)).await;

        assert!(logged.contains("user_id=019238ab-cdef"), "{logged}");
        assert!(!logged.contains(&caller.0.to_string()), "{logged}");
    }

    /// Whatever happened, exactly one record — never none (the defect), never
    /// two (what a level standing in for a field would cost once the feature
    /// logged the cause). A gRPC-Web *success* carries no `grpc-status` header
    /// at all, so the no-status-at-200 case is the ordinary one, not an edge.
    #[tokio::test]
    async fn every_outcome_leaves_exactly_one_record() {
        let cases = [
            (StatusCode::OK, None),
            (StatusCode::OK, Some("0")),
            (StatusCode::OK, Some("13")),
            (StatusCode::NOT_FOUND, None),
            (StatusCode::INTERNAL_SERVER_ERROR, None),
        ];

        for (status, grpc_status) in cases {
            let logged = log_of(RPC, status, grpc_status, None).await;

            assert_eq!(logged.lines().count(), 1, "{logged}");
            assert!(logged.contains(" INFO"), "{logged}");
            assert!(
                logged.contains(&format!("status={}", status.as_u16())),
                "{logged}"
            );
            assert!(logged.contains("duration_ms="), "{logged}");

            if let Some(code) = grpc_status {
                assert!(logged.contains(&format!("grpc_status={code}")), "{logged}");
            }
        }
    }

    /// The noise this exists to remove: a monitor asking a question it has
    /// already been answered two thousand times an hour.
    #[tokio::test]
    async fn a_healthy_probe_leaves_no_record_at_the_default_filter() {
        for path in PROBE_PATHS {
            let logged = log_of(path, StatusCode::OK, None, None).await;

            assert!(logged.is_empty(), "{path}: {logged}");
        }
    }

    /// The half of the rule that keeps the demotion honest. A probe is quiet
    /// because it is *succeeding*, not because of where it points — the
    /// alternative silences the deploy check and the scrape timeout precisely
    /// when they start meaning something.
    #[tokio::test]
    async fn a_failing_probe_is_still_loud() {
        for path in PROBE_PATHS {
            let logged = log_of(path, StatusCode::SERVICE_UNAVAILABLE, None, None).await;

            assert_eq!(logged.lines().count(), 1, "{path}: {logged}");
            assert!(logged.contains(" INFO"), "{path}: {logged}");
            assert!(logged.contains("status=503"), "{path}: {logged}");
        }
    }

    /// Guards the predicate against widening. `/about` is on the same listener
    /// and answers the same way, and nothing asks it on a timer.
    #[tokio::test]
    async fn an_ordinary_route_keeps_its_record() {
        let logged = log_of("/about", StatusCode::OK, None, None).await;

        assert_eq!(logged.lines().count(), 1, "{logged}");
        assert!(logged.contains(" INFO"), "{logged}");
    }

    /// Demoted, not deleted: an assertion that the quiet case logs *nothing*
    /// would pass just as happily against a layer that had stopped recording
    /// probes at all — the defect this module fixed. It also proves the marker
    /// survives the hop from `mark_probes` to the layer above.
    #[tokio::test]
    async fn the_quiet_record_still_exists() {
        let logged = log_of_under(
            "api=info,api::probe=debug,tower_http=info,warn",
            "/health",
            StatusCode::OK,
            None,
            None,
        )
        .await;

        assert_eq!(logged.lines().count(), 1, "{logged}");
        assert!(logged.contains(" DEBUG"), "{logged}");
        assert!(logged.contains("status=200"), "{logged}");
        assert!(logged.contains("duration_ms="), "{logged}");
        assert!(logged.contains("path=/health"), "{logged}");
    }

    /// Exact matches. A prefix rule would hand anyone who can choose a path a
    /// way to log nothing.
    #[test]
    fn only_the_monitored_paths_are_probes() {
        assert!(is_probe("/health"));
        assert!(is_probe("/metrics"));

        for path in [
            "/about",
            "/healthz",
            "/health/",
            "/health/../metrics",
            "/HEALTH",
            "/metrics2",
            RPC,
            "/wp-login.php",
        ] {
            assert!(!is_probe(path), "{path}");
        }
    }
}
