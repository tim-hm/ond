//! One gRPC call's completion, recorded exactly once.
//!
//! The native status arrives in the response head, in the terminal trailers,
//! or never — a body that is dropped or fails mid-stream. This module wraps
//! the body so all three paths record one metric and no path records two.

use std::collections::HashSet;
use std::pin::Pin;
use std::sync::OnceLock;
use std::task::{Context, Poll};
use std::time::{Duration, Instant};

use axum::body::{Body, Bytes, HttpBody};
use axum::http::HeaderMap;
use axum::response::Response;
use http_body::{Frame, SizeHint};
use metrics::{counter, histogram};
use prost::Message;
use prost_types::FileDescriptorSet;
use tonic::Code;

use crate::proto::ond::v1::FILE_DESCRIPTOR_SET;

const GRPC_STATUS: &str = "grpc-status";

pub(super) fn instrument_grpc_response<F>(
    response: Response,
    started: Instant,
    complete: F,
) -> Response
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
/// The invariant both transport families follow: counters carry the outcome,
/// histograms carry the operation. The obvious alternative — `method` and
/// `status` on both — multiplies the histogram's per-bucket series by
/// seventeen codes, to answer a question nobody asks (how slowly a call
/// failed). Which call is slow and which is failing are one label each.
pub(super) fn record_grpc_completion(method: &'static str, code: Code, elapsed: Duration) {
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
pub(super) fn method_label(path: &str) -> &'static str {
    methods().get(path).map_or("other", String::as_str)
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
