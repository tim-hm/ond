//! Decodes and relays Bedrock's streaming event protocol.
//!
//! The provider may split text and tool JSON at arbitrary frame boundaries, or
//! keep a stream alive without advancing it. This module assembles only the
//! bounded state needed for one tool call and enforces both idle and absolute
//! deadlines before a decoded chunk reaches the provider-independent model
//! stream.

use std::time::{Duration, Instant};

use serde::Deserialize;
use tokio::sync::mpsc;

use super::super::super::metrics;
use super::super::types::millis;
use super::super::{ModelChunk, ModelError};
use crate::config;

/// Bounds the tool input a stream may assemble.
///
/// The saved-exercise tool has the largest declared shape: a short name and
/// summary plus nested stages and phases. Eight KiB leaves ample room for every
/// valid draft while preventing a runaway model from growing an unbounded JSON
/// buffer across the provider boundary. Crossing the bound drops the tool call
/// and keeps the prose.
pub(super) const MAX_TOOL_INPUT_BYTES: usize = 8 * 1024;

/// The longest silence accepted between provider events.
///
/// Pings count as activity. The iOS client's 40-second streaming idle timer is
/// deliberately above this, so the server returns a reportable failure first.
pub(super) const STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(30);

/// The absolute lifetime of a provider stream after its response opens.
///
/// Three minutes is well beyond a compliant 850-token Chat reply but still
/// bounds a provider that keeps sending pings or tiny deltas inside every idle
/// window forever.
const STREAM_LIFETIME: Duration = Duration::from_mins(3);

/// One provider tool block while its JSON fragments arrive.
#[derive(Default)]
pub(super) struct ToolAssembly {
    /// The open call's name and the input JSON its deltas have delivered.
    open: Option<(String, String)>,
}

impl ToolAssembly {
    /// Opens a named tool call if no other call is being assembled.
    ///
    /// Empty names and overlapping starts are dropped: neither can be
    /// dispatched safely, and replacing an open call would attach its remaining
    /// JSON fragments to a different tool.
    pub(super) fn start(&mut self, name: String) {
        if !name.is_empty() && self.open.is_none() {
            self.open = Some((name, String::new()));
        }
    }

    /// Appends one JSON fragment, dropping the call if it crosses the bound.
    ///
    /// Once dropped, later deltas and the closing boundary are harmless no-ops,
    /// which keeps malformed tool input from taking otherwise useful prose with
    /// it.
    pub(super) fn append(&mut self, json: &str) {
        if let Some((_, input)) = self.open.as_mut() {
            if input.len() + json.len() > MAX_TOOL_INPUT_BYTES {
                tracing::warn!(
                    feature = "assistant",
                    "the tool input outgrew its bound; dropping the tool call"
                );
                self.open = None;
            } else {
                input.push_str(json);
            }
        }
    }

    /// The completed call on the block boundary that closes it.
    pub(super) fn finish(&mut self) -> Option<ModelChunk> {
        let (name, input_json) = self.open.take()?;
        Some(ModelChunk::ToolUse { name, input_json })
    }
}

/// One decoded stream frame, reduced to what matters.
pub(super) enum Event {
    /// Text to append to the reply.
    Text(String),
    /// A `tool_use` content block opened: the model is calling the named tool,
    /// and its input follows as [`Event::ToolInputDelta`] fragments.
    ToolUseStart { name: String },
    /// The next fragment of an open tool call's input JSON.
    ToolInputDelta(String),
    /// A content block closed. Meaningful only while a tool call is open —
    /// it is what says the input JSON is complete; a text block's close says
    /// nothing the deltas did not.
    BlockStop,
    /// The provider said the stream is over.
    Done,
    /// The provider reported a failure inside a stream it had already opened —
    /// how a throttle or an upstream outage arrives once the response is
    /// committed to a 200 and the headers are long gone.
    Failed(Option<String>),
    /// What the provider has billed so far. Arrives twice and in two shapes:
    /// `message_start` carries the prompt and any cache read, `message_delta`
    /// carries the completion, and each reports only its own half.
    ///
    /// An event rather than a side effect inside the parser, because
    /// [`parse_event`] is pure and unit-tested and should stay both. The relay
    /// is where events turn into consequences.
    Usage {
        prompt: u32,
        completion: u32,
        cached: u32,
        cache_written: u32,
    },
    /// A ping or a text block opening — every stream has several, and none of
    /// them is an error.
    Ignored,
}

/// A decoded provider-event source the relay can cancel by dropping.
///
/// Kept provider-neutral so timeout, empty-stream, and cancellation behaviour
/// can be tested with a scripted source rather than an AWS connection.
#[tonic::async_trait]
pub(super) trait EventSource: Send {
    /// Returns the next meaningful event, or `None` when the provider closes.
    async fn next(&mut self) -> Result<Option<Event>, ModelError>;
}

/// Relays decoded provider events into the model stream.
///
/// The output receiver owns cancellation: once its reader disappears, the
/// provider source is dropped even if it is waiting for another frame. Silence
/// is bounded independently from total lifetime, so neither a stalled source
/// nor one that emits forever can retain the provider call. A clean end without
/// text or a tool call is an error because an empty successful RPC leaves the
/// client with a sent message and no answer.
pub(super) async fn relay_events<S: EventSource>(
    source: S,
    sender: mpsc::Sender<Result<ModelChunk, ModelError>>,
    started: Option<Instant>,
    request_id: Option<&str>,
) {
    relay_events_with_timeouts(
        source,
        sender,
        started,
        request_id,
        STREAM_IDLE_TIMEOUT,
        STREAM_LIFETIME,
    )
    .await;
}

async fn relay_events_with_timeouts<S: EventSource>(
    source: S,
    sender: mpsc::Sender<Result<ModelChunk, ModelError>>,
    started: Option<Instant>,
    request_id: Option<&str>,
    idle_timeout: Duration,
    lifetime: Duration,
) {
    let expiry_sender = sender.clone();
    tokio::select! {
        () = relay_until_end(source, sender, started, request_id, idle_timeout) => {}
        () = tokio::time::sleep(lifetime) => {
            let expired = refused(
                "the provider stream exceeded its absolute lifetime",
                None,
                request_id,
            );
            drop(expiry_sender.send(Err(expired)).await);
        }
    }
}

async fn relay_until_end<S: EventSource>(
    mut source: S,
    sender: mpsc::Sender<Result<ModelChunk, ModelError>>,
    mut started: Option<Instant>,
    request_id: Option<&str>,
    idle_timeout: Duration,
) {
    let mut answered = false;
    let mut tool = ToolAssembly::default();

    loop {
        let event = tokio::select! {
            event = tokio::time::timeout(idle_timeout, source.next()) => if let Ok(event) = event {
                event
            } else {
                let stalled = refused(
                    "the provider stream was idle for too long",
                    None,
                    request_id,
                );
                drop(sender.send(Err(stalled)).await);
                return;
            },
            () = sender.closed() => return,
        };

        let event = match event {
            Ok(Some(event)) => event,
            Ok(None) => break,
            Err(error) => {
                drop(sender.send(Err(error)).await);
                return;
            }
        };

        match event {
            Event::Done => break,
            Event::Failed(kind) => {
                let failed = refused(
                    "the provider failed mid-stream",
                    kind.as_deref(),
                    request_id,
                );
                drop(sender.send(Err(failed)).await);
                return;
            }
            Event::Text(text) if !text.is_empty() => {
                let said_something = !text.trim().is_empty();
                if sender.send(Ok(ModelChunk::Text(text))).await.is_err() {
                    return;
                }
                record_first_chunk(&mut started);
                answered = answered || said_something;
            }
            Event::ToolUseStart { name } => tool.start(name),
            Event::ToolInputDelta(json) => tool.append(&json),
            Event::BlockStop => {
                if let Some(chunk) = tool.finish() {
                    if sender.send(Ok(chunk)).await.is_err() {
                        return;
                    }
                    record_first_chunk(&mut started);
                    answered = true;
                }
            }
            Event::Usage {
                prompt,
                completion,
                cached,
                cache_written,
            } => metrics::tokens(prompt, completion, cached, cache_written),
            Event::Text(_) | Event::Ignored => {}
        }
    }

    if !answered {
        drop(
            sender
                .send(Err(ModelError::Failed(
                    "the provider's stream carried no content".to_owned(),
                )))
                .await,
        );
    }
}

/// Records time to first token, once per stream that produces one.
///
/// The line is `debug` because it carries nothing the histogram beside it does
/// not: it is a per-call record of a number already being aggregated, and the
/// question it answers — "how long did this one stream take to start" — is a
/// debugging question rather than a permanent one.
fn record_first_chunk(started: &mut Option<Instant>) {
    if let Some(started) = started.take() {
        tracing::debug!(
            feature = "assistant",
            model = config::BEDROCK_MODEL_ID,
            duration_ms = millis(started.elapsed()),
            "the model started answering"
        );
        metrics::time_to_first_token(started.elapsed());
    }
}

/// Names a provider failure by its error code and request id, never its prose.
///
/// Provider messages may quote a person's input, so only safe metadata crosses
/// this boundary into logs and client-visible errors.
pub(super) fn refused(context: &str, code: Option<&str>, request_id: Option<&str>) -> ModelError {
    let mut message = match code {
        Some(code) => format!("{context}: {code}"),
        None => context.to_owned(),
    };
    if let Some(id) = request_id {
        message = format!("{message} (request {id})");
    }
    ModelError::Failed(message)
}

/// Reads one event frame.
///
/// A frame that does not parse is skipped rather than failing the stream: the
/// person is reading a reply, and losing a sentence beats losing the rest
/// of it. The error arm is checked before the delta for the reason it exists —
/// an error read as `Ignored` is a stream that simply stopped, which the caller
/// cannot tell from a finished answer.
pub(super) fn parse_event(payload: &[u8]) -> Event {
    let Ok(frame) = serde_json::from_slice::<StreamFrame>(payload) else {
        return Event::Ignored;
    };

    match frame.kind.as_str() {
        "error" => Event::Failed(frame.error.and_then(|error| error.kind)),
        "message_stop" => Event::Done,
        // The two halves of the bill. The prompt and any cache read are known
        // when the message opens; the completion only once it closes. Neither
        // frame reports the other's numbers, so both are read and the counters
        // add them up.
        "message_start" => frame
            .message
            .and_then(|message| message.usage)
            .map_or(Event::Ignored, Usage::into_event),
        "message_delta" => frame.usage.map_or(Event::Ignored, Usage::into_event),
        "content_block_start" => frame
            .content_block
            .filter(|block| block.kind == "tool_use")
            .and_then(|block| block.name)
            .filter(|name| !name.is_empty())
            .map_or(Event::Ignored, |name| Event::ToolUseStart { name }),
        "content_block_stop" => Event::BlockStop,
        "content_block_delta" => match frame.delta {
            Some(Delta {
                text: Some(text), ..
            }) => Event::Text(text),
            Some(Delta {
                partial_json: Some(json),
                ..
            }) => Event::ToolInputDelta(json),
            _ => Event::Ignored,
        },
        _ => Event::Ignored,
    }
}

/// One frame of the event stream, in the shape shared by all event kinds.
#[derive(Deserialize)]
struct StreamFrame {
    #[serde(rename = "type", default)]
    kind: String,
    #[serde(default)]
    delta: Option<Delta>,
    #[serde(default)]
    content_block: Option<ContentBlockStart>,
    #[serde(default)]
    error: Option<StreamError>,
    /// `message_delta` reports the completion here.
    #[serde(default)]
    usage: Option<Usage>,
    /// `message_start` nests its own report one level down.
    #[serde(default)]
    message: Option<MessageStart>,
}

#[derive(Deserialize)]
struct MessageStart {
    #[serde(default)]
    usage: Option<Usage>,
}

/// Whatever the frame reported, with the halves it did not mention left at zero.
///
/// Every field defaults rather than being required: the two frames that carry
/// usage carry different subsets of it, and a missing field is "not billed in
/// this frame" rather than a malformed stream. A `deny_unknown_fields` or a
/// required field here would turn a provider adding a token category into a
/// stream that stops decoding.
/// The field names are the provider's, not ours — this is a wire shape, and
/// renaming them to satisfy a lint about shared postfixes would mean three
/// `#[serde(rename)]` attributes to say the same thing less directly.
#[derive(Deserialize)]
#[allow(
    clippy::struct_field_names,
    reason = "the names are Bedrock's own; renaming them buys three serde renames and no clarity"
)]
struct Usage {
    #[serde(default)]
    input_tokens: u32,
    #[serde(default)]
    output_tokens: u32,
    #[serde(default)]
    cache_read_input_tokens: u32,
    /// Tokens written into the cache, billed at 1.25× the base rate. Charged
    /// whenever the cached prefix changes or its five-minute entry has lapsed,
    /// so a low-traffic coach pays this far more often than a busy one.
    #[serde(default)]
    cache_creation_input_tokens: u32,
}

impl Usage {
    const fn into_event(self) -> Event {
        Event::Usage {
            prompt: self.input_tokens,
            completion: self.output_tokens,
            cached: self.cache_read_input_tokens,
            cache_written: self.cache_creation_input_tokens,
        }
    }
}

#[derive(Deserialize)]
struct Delta {
    #[serde(default)]
    text: Option<String>,
    /// The next fragment of a tool call's input, on `input_json_delta` frames.
    #[serde(default)]
    partial_json: Option<String>,
}

/// The opening of one content block, read only to recognise a `tool_use`.
#[derive(Deserialize)]
struct ContentBlockStart {
    #[serde(rename = "type", default)]
    kind: String,
    #[serde(default)]
    name: Option<String>,
}

/// A mid-stream failure, reduced to the one field that is safe to keep.
///
/// The sibling `message` is deliberately not read, for the reason [`refused`]
/// gives: it is where a moderation refusal quotes the person's own words back.
#[derive(Deserialize)]
struct StreamError {
    #[serde(rename = "type", default)]
    kind: Option<String>,
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    use super::*;

    struct ScriptedSource {
        events: VecDeque<Result<Option<Event>, ModelError>>,
    }

    #[tonic::async_trait]
    impl EventSource for ScriptedSource {
        async fn next(&mut self) -> Result<Option<Event>, ModelError> {
            self.events.pop_front().unwrap_or(Ok(None))
        }
    }

    async fn relay(
        events: Vec<Result<Option<Event>, ModelError>>,
    ) -> Vec<Result<ModelChunk, ModelError>> {
        let source = ScriptedSource {
            events: events.into(),
        };
        let (sender, mut receiver) = mpsc::channel(8);
        relay_events(source, sender, None, None).await;

        let mut chunks = Vec::new();
        while let Some(chunk) = receiver.recv().await {
            chunks.push(chunk);
        }
        chunks
    }

    #[tokio::test]
    async fn text_is_relayed_in_provider_order() {
        let chunks = relay(vec![
            Ok(Some(Event::Text("one".to_owned()))),
            Ok(Some(Event::Text(" two".to_owned()))),
            Ok(Some(Event::Done)),
        ])
        .await;

        let chunks = chunks
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("the scripted stream succeeds");
        assert_eq!(
            chunks,
            vec![
                ModelChunk::Text("one".to_owned()),
                ModelChunk::Text(" two".to_owned()),
            ]
        );
    }

    #[tokio::test]
    async fn an_empty_stream_is_an_error() {
        let chunks = relay(vec![Ok(Some(Event::Done))]).await;

        assert_eq!(chunks.len(), 1);
        assert!(
            chunks[0]
                .as_ref()
                .expect_err("an empty stream fails")
                .to_string()
                .contains("carried no content")
        );
    }

    #[tokio::test]
    async fn a_source_error_is_forwarded() {
        let chunks = relay(vec![Err(ModelError::Failed("stream failed".to_owned()))]).await;

        assert_eq!(chunks.len(), 1);
        assert!(
            chunks[0]
                .as_ref()
                .expect_err("the source failure is forwarded")
                .to_string()
                .contains("stream failed")
        );
    }

    #[tokio::test]
    async fn an_idle_source_fails_inside_the_absolute_lifetime() {
        let dropped = Arc::new(AtomicBool::new(false));
        let source = PendingSource {
            dropped: Arc::clone(&dropped),
        };
        let (sender, mut receiver) = mpsc::channel(1);

        relay_events_with_timeouts(
            source,
            sender,
            None,
            None,
            Duration::from_millis(10),
            Duration::from_secs(1),
        )
        .await;

        let error = receiver
            .recv()
            .await
            .expect("the idle failure arrives")
            .expect_err("an idle stream fails");
        assert!(error.to_string().contains("idle for too long"));
        assert!(dropped.load(Ordering::SeqCst));
    }

    struct HeartbeatSource {
        calls: Arc<AtomicUsize>,
        dropped: Arc<AtomicBool>,
    }

    impl Drop for HeartbeatSource {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    #[tonic::async_trait]
    impl EventSource for HeartbeatSource {
        async fn next(&mut self) -> Result<Option<Event>, ModelError> {
            tokio::time::sleep(Duration::from_millis(2)).await;
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(Some(Event::Ignored))
        }
    }

    #[tokio::test]
    async fn activity_does_not_extend_the_absolute_lifetime() {
        let calls = Arc::new(AtomicUsize::new(0));
        let dropped = Arc::new(AtomicBool::new(false));
        let source = HeartbeatSource {
            calls: Arc::clone(&calls),
            dropped: Arc::clone(&dropped),
        };
        let (sender, mut receiver) = mpsc::channel(1);

        relay_events_with_timeouts(
            source,
            sender,
            None,
            None,
            Duration::from_millis(25),
            Duration::from_millis(40),
        )
        .await;

        let error = receiver
            .recv()
            .await
            .expect("the lifetime failure arrives")
            .expect_err("an overlong stream fails");
        assert!(error.to_string().contains("absolute lifetime"));
        assert!(
            calls.load(Ordering::SeqCst) > 1,
            "events kept the stream active"
        );
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn a_tool_call_can_be_the_first_answer() {
        let chunks = relay(vec![
            Ok(Some(Event::ToolUseStart {
                name: "offer_exercise".to_owned(),
            })),
            Ok(Some(Event::ToolInputDelta("{\"slug\":\"box\"}".to_owned()))),
            Ok(Some(Event::BlockStop)),
            Ok(Some(Event::Text("why it fits".to_owned()))),
            Ok(Some(Event::Done)),
        ])
        .await;

        let chunks = chunks
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("the scripted stream succeeds");
        assert_eq!(
            chunks,
            vec![
                ModelChunk::ToolUse {
                    name: "offer_exercise".to_owned(),
                    input_json: "{\"slug\":\"box\"}".to_owned(),
                },
                ModelChunk::Text("why it fits".to_owned()),
            ]
        );
    }

    struct PendingSource {
        dropped: Arc<AtomicBool>,
    }

    impl Drop for PendingSource {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    #[tonic::async_trait]
    impl EventSource for PendingSource {
        async fn next(&mut self) -> Result<Option<Event>, ModelError> {
            std::future::pending().await
        }
    }

    #[tokio::test]
    async fn dropping_the_reader_cancels_the_source() {
        let dropped = Arc::new(AtomicBool::new(false));
        let source = PendingSource {
            dropped: Arc::clone(&dropped),
        };
        let (sender, receiver) = mpsc::channel(1);
        drop(receiver);

        tokio::time::timeout(
            std::time::Duration::from_millis(100),
            relay_events(source, sender, None, None),
        )
        .await
        .expect("relay notices cancellation");
        assert!(dropped.load(Ordering::SeqCst));
    }
}
