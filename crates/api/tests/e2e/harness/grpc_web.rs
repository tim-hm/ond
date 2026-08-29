//! A gRPC-Web client that drives the production router in memory.

use std::collections::HashMap;

use axum::Router;
use axum::body::{Body, Bytes};
use axum::http::{Request, StatusCode, header};
use prost::Message;
use tower::ServiceExt;

/// One flag byte, then a four-byte big-endian length.
const FRAME_HEADER_LEN: usize = 5;

/// The high bit of the flag byte marks a trailer frame rather than a message.
const TRAILER_FLAG: u8 = 0x80;

/// Generous enough for the whole catalogue and small enough that a runaway
/// response fails the test instead of the machine.
const MAX_RESPONSE_BYTES: usize = 1 << 20;

/// A deframed gRPC-Web response.
pub struct GrpcWebResponse<T> {
    /// Absent when the call failed before producing a message, which is what a
    /// trailers-only error response looks like.
    pub message: Option<T>,
    /// The `grpc-status` code. `0` is success and the rest match `tonic::Code`.
    pub status: i32,
    /// The `grpc-message` text, empty on success.
    pub status_message: String,
}

impl<T> GrpcWebResponse<T> {
    /// The message, asserting the call succeeded.
    pub fn into_ok(self) -> T {
        assert_eq!(
            self.status, 0,
            "grpc-status {}: {}",
            self.status, self.status_message
        );
        self.message
            .expect("a successful call carries a message frame")
    }
}

/// Calls `path` the way the iOS client does. gRPC-Web is an HTTP POST carrying
/// a length-prefixed protobuf frame, with the call's outcome in trailers — so
/// a failed call still returns 200, which is why this goes over the real
/// framing. Driving the router with `oneshot` rather than binding a port is
/// deliberate: a listener would only add hyper, a background task, and a shutdown race.
pub async fn call_grpc_web<Req, Res>(app: Router, path: &str, request: &Req) -> GrpcWebResponse<Res>
where
    Req: Message,
    Res: Message + Default,
{
    call_grpc_web_with(app, path, request, &[]).await
}

/// [`call_grpc_web`], plus the headers the client would send alongside.
///
/// Separate rather than a fourth parameter on every call site: identity is the
/// only thing that travels out-of-band, and the tests that do not exercise it
/// read better without an empty slice in them.
pub async fn call_grpc_web_with<Req, Res>(
    app: Router,
    path: &str,
    request: &Req,
    headers: &[(&str, &str)],
) -> GrpcWebResponse<Res>
where
    Req: Message,
    Res: Message + Default,
{
    let streamed = call_grpc_web_stream_with(app, path, request, headers).await;

    assert!(
        streamed.messages.len() <= 1,
        "a unary call answered with {} messages",
        streamed.messages.len()
    );

    GrpcWebResponse {
        message: streamed.messages.into_iter().next(),
        status: streamed.status,
        status_message: streamed.status_message,
    }
}

/// Every message a server-streaming call produced, plus how it ended.
///
/// Separate from [`GrpcWebResponse`] because the thing being asserted is
/// different: a unary call has one message or none, and a stream has an ordered
/// list whose order is the point.
pub struct GrpcWebStream<T> {
    /// In the order they arrived on the wire.
    pub messages: Vec<T>,
    pub status: i32,
    pub status_message: String,
}

impl<T> GrpcWebStream<T> {
    /// The messages, asserting the stream ended cleanly.
    pub fn into_ok(self) -> Vec<T> {
        assert_eq!(
            self.status, 0,
            "grpc-status {}: {}",
            self.status, self.status_message
        );
        self.messages
    }
}

/// Calls a server-streaming method the way the iOS client does. gRPC-Web sends
/// a server stream as several length-prefixed frames in one response body,
/// followed by the trailer frame — readable here without a listener, in the
/// order the server wrote them, which is what a client accumulating an
/// explanation depends on and is only observable through the real framing.
pub async fn call_grpc_web_stream_with<Req, Res>(
    app: Router,
    path: &str,
    request: &Req,
    headers: &[(&str, &str)],
) -> GrpcWebStream<Res>
where
    Req: Message,
    Res: Message + Default,
{
    let mut builder =
        Request::post(path).header(header::CONTENT_TYPE, "application/grpc-web+proto");
    for (name, value) in headers {
        builder = builder.header(*name, *value);
    }

    let response = app
        .oneshot(
            builder
                .body(Body::from(frame(request)))
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");

    // Anything other than 200 is a transport-level failure — a path tonic does
    // not route, or a request `GrpcWebLayer` refused to unwrap.
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "gRPC-Web reports call outcomes in trailers, so {path} should answer 200 either way"
    );

    // tonic answers an error that occurs before the response body with headers
    // alone, and a later one with a trailer frame. Both arrive here.
    let mut trailers: HashMap<String, String> = response
        .headers()
        .iter()
        .filter(|(name, _)| name.as_str().starts_with("grpc-"))
        .filter_map(|(name, value)| {
            Some((name.as_str().to_owned(), value.to_str().ok()?.to_owned()))
        })
        .collect();

    let body = axum::body::to_bytes(response.into_body(), MAX_RESPONSE_BYTES)
        .await
        .expect("the response body is readable");

    let messages = deframe(&body, &mut trailers);

    let status = trailers
        .get("grpc-status")
        .and_then(|value| value.parse().ok())
        .expect("the response carries a grpc-status, in a header or a trailer frame");

    GrpcWebStream {
        messages,
        status,
        status_message: trailers.get("grpc-message").cloned().unwrap_or_default(),
    }
}

fn frame(message: &impl Message) -> Bytes {
    let payload = message.encode_to_vec();
    let length = u32::try_from(payload.len()).expect("a request smaller than 4 GiB");

    let mut framed = Vec::with_capacity(FRAME_HEADER_LEN + payload.len());
    framed.push(0);
    framed.extend_from_slice(&length.to_be_bytes());
    framed.extend_from_slice(&payload);

    Bytes::from(framed)
}

/// Walks the frames in `body`, decoding every message and folding any trailer
/// frame into `trailers`.
///
/// A `Vec` rather than one message because a server stream writes several into
/// the same body; a unary call produces a list of one.
fn deframe<Res: Message + Default>(
    body: &[u8],
    trailers: &mut HashMap<String, String>,
) -> Vec<Res> {
    let mut messages = Vec::new();
    let mut rest = body;

    while rest.len() >= FRAME_HEADER_LEN {
        let flags = rest[0];
        let length = u32::from_be_bytes(
            rest[1..FRAME_HEADER_LEN]
                .try_into()
                .expect("a four-byte slice"),
        );
        let length = usize::try_from(length).expect("a frame that fits in memory");

        let end = FRAME_HEADER_LEN + length;
        assert!(
            end <= rest.len(),
            "frame claims {length} bytes it does not have"
        );
        let payload = &rest[FRAME_HEADER_LEN..end];
        rest = &rest[end..];

        if flags & TRAILER_FLAG == 0 {
            messages.push(Res::decode(payload).expect("the message frame decodes"));
        } else {
            let text = std::str::from_utf8(payload).expect("trailers are UTF-8");
            for line in text.lines() {
                if let Some((name, value)) = line.split_once(':') {
                    trailers.insert(name.trim().to_ascii_lowercase(), value.trim().to_owned());
                }
            }
        }
    }

    assert!(rest.is_empty(), "trailing bytes after the last frame");
    messages
}
