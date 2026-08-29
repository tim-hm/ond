//! Prometheus recorder mechanics and transport-wide request metrics. Product
//! gauges live with the feature that defines their meaning; this module owns
//! the process recorder and the two transport boundaries: ordinary HTTP at the
//! outer router, and native gRPC inside the gRPC-Web envelope where final
//! trailers remain observable.

use std::collections::HashSet;
use std::pin::Pin;
use std::sync::OnceLock;
use std::task::{Context, Poll};
use std::time::{Duration, Instant};

use axum::body::{Body, Bytes, HttpBody};
use axum::extract::Request;
use axum::http::{HeaderMap, StatusCode};
use axum::middleware::Next;
use axum::response::Response;
use http_body::{Frame, SizeHint};
use metrics::{counter, gauge, histogram};
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};
use prost::Message;
use prost_types::FileDescriptorSet;
use tonic::Code;

use crate::proto::ond::v1::FILE_DESCRIPTOR_SET;

/// Latency buckets, in seconds, chosen around what this server actually does:
/// screen-open gRPC calls are single-digit milliseconds and the assistant's
/// streaming turn is seconds, so both ends need resolution — the bounds are
/// wide and the middle is coarse.
const LATENCY_BUCKETS: &[f64] = &[
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

const GRPC_STATUS: &str = "grpc-status";

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
    reason = "num_idle is bounded by max_connections, which is ten"
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

fn instrument_grpc_response<F>(response: Response, started: Instant, complete: F) -> Response
where
    F: FnOnce(Code, Duration) + Send + 'static,
{
    let (parts, body) = response.into_parts();
    let mut completion = Completion::new(started, Box::new(complete));

    if let Some(code) = grpc_code(&parts.headers) {
        completion.finish(code);
    }

    Response::from_parts(
        parts,
        Body::new(CompletionBody {
            body: Box::pin(body),
            completion,
        }),
    )
}

type CompletionCallback = Box<dyn FnOnce(Code, Duration) + Send>;

struct Completion {
    started: Instant,
    complete: Option<CompletionCallback>,
}

impl Completion {
    fn new(started: Instant, complete: CompletionCallback) -> Self {
        Self {
            started,
            complete: Some(complete),
        }
    }

    fn finish(&mut self, code: Code) {
        if let Some(complete) = self.complete.take() {
            complete(code, self.started.elapsed());
        }
    }
}

struct CompletionBody {
    body: Pin<Box<Body>>,
    completion: Completion,
}

impl HttpBody for CompletionBody {
    type Data = Bytes;
    type Error = axum::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let this = self.get_mut();
        let polled = this.body.as_mut().poll_frame(context);

        match &polled {
            Poll::Ready(Some(Ok(frame))) => {
                if let Some(trailers) = frame.trailers_ref() {
                    this.completion
                        .finish(grpc_code(trailers).unwrap_or(Code::Unknown));
                }
            }
            Poll::Ready(Some(Err(_)) | None) => {
                this.completion.finish(Code::Unknown);
            }
            Poll::Pending => {}
        }

        polled
    }

    fn is_end_stream(&self) -> bool {
        self.body.is_end_stream()
    }

    fn size_hint(&self) -> SizeHint {
        self.body.size_hint()
    }
}

impl Drop for CompletionBody {
    fn drop(&mut self) {
        self.completion.finish(Code::Unknown);
    }
}

fn grpc_code(headers: &HeaderMap) -> Option<Code> {
    let value = headers.get(GRPC_STATUS)?;
    let code = value
        .to_str()
        .ok()
        .and_then(|value| value.parse::<i32>().ok())
        .map_or(Code::Unknown, Code::from_i32);
    Some(code)
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

/// The invariant both transport families follow: counters carry the outcome,
/// histograms carry the operation. The obvious alternative — `method` and
/// `status` on both — multiplies the histogram's per-bucket series by
/// seventeen codes, to answer a question nobody asks (how slowly a call
/// failed). Which call is slow and which is failing are one label each.
fn record_grpc_completion(method: &'static str, code: Code, elapsed: Duration) {
    let status = grpc_status_label(code);
    counter!(
        "ond_grpc_requests_total",
        "method" => method,
        "status" => status
    )
    .increment(1);
    histogram!("ond_grpc_request_duration_seconds", "method" => method)
        .record(elapsed.as_secs_f64());
}

const fn grpc_status_label(code: Code) -> &'static str {
    match code {
        Code::Ok => "0",
        Code::Cancelled => "1",
        Code::Unknown => "2",
        Code::InvalidArgument => "3",
        Code::DeadlineExceeded => "4",
        Code::NotFound => "5",
        Code::AlreadyExists => "6",
        Code::PermissionDenied => "7",
        Code::ResourceExhausted => "8",
        Code::FailedPrecondition => "9",
        Code::Aborted => "10",
        Code::OutOfRange => "11",
        Code::Unimplemented => "12",
        Code::Internal => "13",
        Code::Unavailable => "14",
        Code::DataLoss => "15",
        Code::Unauthenticated => "16",
    }
}

/// Every RPC path the contract defines, read from the descriptor set
/// `build.rs` emits rather than hand-kept — a hand-kept list fails silently:
/// an RPC added to the .proto but not the list records as `other` while the
/// call it cannot name is the one failing. Built once, so a label is a hash
/// and no allocation. A set that will not decode stays empty: degraded metrics, not a failed boot.
static METHODS: OnceLock<HashSet<String>> = OnceLock::new();

fn methods() -> &'static HashSet<String> {
    METHODS.get_or_init(|| {
        let descriptors = match FileDescriptorSet::decode(FILE_DESCRIPTOR_SET) {
            Ok(descriptors) => descriptors,
            Err(error) => {
                tracing::error!(%error, "could not read the descriptor set; gRPC metrics will not name a method");
                return HashSet::new();
            }
        };

        descriptors
            .file
            .iter()
            .flat_map(|file| {
                let package = file.package();
                file.service.iter().flat_map(move |service| {
                    let service_name = service.name();
                    service
                        .method
                        .iter()
                        .map(move |method| format!("/{package}.{service_name}/{}", method.name()))
                })
            })
            .collect()
    })
}

/// Collapses a gRPC path to the method it names, or `other`. The membership
/// test is the cardinality bound: taking the path straight off the URI would
/// let anything that can reach this server mint a time series per request;
/// membership caps the label set at the number of RPCs in `proto/`.
fn method_label(path: &str) -> &'static str {
    methods().get(path).map_or("other", String::as_str)
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

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::io;
    use std::sync::{Arc, Mutex};

    use axum::body::{Bytes, to_bytes};
    use axum::http::{HeaderValue, Response as HttpResponse};
    use http_body_util::{BodyExt, Full, StreamBody};

    use super::*;

    fn status_headers(code: i32) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(
            GRPC_STATUS,
            HeaderValue::from_str(&code.to_string()).unwrap(),
        );
        headers
    }

    async fn completion_of(response: Response) -> Vec<Code> {
        let completed = Arc::new(Mutex::new(Vec::new()));
        let captured = Arc::clone(&completed);
        let response = instrument_grpc_response(response, Instant::now(), move |code, _| {
            captured.lock().unwrap().push(code);
        });

        to_bytes(response.into_body(), usize::MAX).await.unwrap();
        Arc::try_unwrap(completed).unwrap().into_inner().unwrap()
    }

    fn trailers_only(code: i32) -> Response {
        let body = Full::<Bytes>::default()
            .with_trailers(async move { Some(Ok::<_, Infallible>(status_headers(code))) });
        HttpResponse::new(Body::new(body))
    }

    fn response_head(code: i32) -> Response {
        let mut response = HttpResponse::new(Body::empty());
        *response.headers_mut() = status_headers(code);
        response
    }

    /// The descriptor set really does decode, and really does contain the
    /// contract. Without this the `methods()` failure path is indistinguishable
    /// from success: an empty set labels everything `other`, every metric keeps
    /// being recorded, and nothing anywhere says the method label stopped
    /// working.
    #[test]
    fn every_rpc_in_the_contract_has_a_label() {
        let methods = methods();

        assert!(
            !methods.is_empty(),
            "the descriptor set did not decode; every call would record as `other`"
        );
        assert!(methods.contains("/ond.v1.TechniqueService/ListTechniques"));
        // The money path, named here because it is the RPC alerts.yml wanted to
        // narrow to and could not while the counter carried only a status.
        assert!(methods.contains("/ond.v1.EntitlementService/SubmitAppStoreTransaction"));
        // A server-streaming RPC, whose status arrives in trailers rather than
        // the response head. The method label has to survive that longer path.
        assert!(methods.contains("/ond.v1.AssistantService/Chat"));
        assert!(
            methods.iter().all(|path| path.starts_with("/ond.v1.")),
            "a path outside the contract's package reached the label set"
        );
    }

    /// Cardinality is the reason this label is a membership test rather than
    /// the path itself. A scanner walking made-up RPC names must not be able to
    /// mint a series each.
    #[test]
    fn paths_outside_the_contract_collapse_to_other() {
        assert_eq!(method_label("/ond.v1.TechniqueService/Invented"), "other");
        assert_eq!(method_label("/ond.v1.NoSuchService/Method"), "other");
        assert_eq!(method_label("/wp-login.php"), "other");
        assert_eq!(
            method_label("/ond.v1.TechniqueService/ListTechniques"),
            "/ond.v1.TechniqueService/ListTechniques"
        );
    }

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

    #[tokio::test]
    async fn unary_success_and_failure_use_native_status() {
        assert_eq!(completion_of(trailers_only(0)).await, vec![Code::Ok]);
        assert_eq!(completion_of(response_head(13)).await, vec![Code::Internal]);
    }

    #[tokio::test]
    async fn auth_and_throttle_refusals_complete_at_the_native_boundary() {
        assert_eq!(
            completion_of(response_head(16)).await,
            vec![Code::Unauthenticated]
        );
        assert_eq!(
            completion_of(response_head(8)).await,
            vec![Code::ResourceExhausted]
        );
    }

    #[tokio::test]
    async fn a_mid_stream_failure_uses_the_terminal_trailer() {
        let body = Full::new(Bytes::from_static(b"one"))
            .with_trailers(async { Some(Ok::<_, Infallible>(status_headers(13))) });
        let response = HttpResponse::new(Body::new(body));

        assert_eq!(completion_of(response).await, vec![Code::Internal]);
    }

    #[tokio::test]
    async fn status_labels_are_bounded_to_native_codes() {
        assert_eq!(completion_of(response_head(999)).await, vec![Code::Unknown]);
    }

    #[tokio::test]
    async fn a_body_ending_without_status_completes_once_as_unknown() {
        assert_eq!(
            completion_of(HttpResponse::new(Body::empty())).await,
            vec![Code::Unknown]
        );
    }

    #[tokio::test]
    async fn a_body_error_without_status_completes_once_as_unknown() {
        let body = StreamBody::new(tokio_stream::iter([Err::<Frame<Bytes>, _>(
            io::Error::other("body failed"),
        )]));
        let response = HttpResponse::new(Body::new(body));
        let completed = Arc::new(Mutex::new(Vec::new()));
        let captured = Arc::clone(&completed);
        let response = instrument_grpc_response(response, Instant::now(), move |code, _| {
            captured.lock().unwrap().push(code);
        });

        assert!(to_bytes(response.into_body(), usize::MAX).await.is_err());
        assert_eq!(
            Arc::try_unwrap(completed).unwrap().into_inner().unwrap(),
            vec![Code::Unknown]
        );
    }
}
