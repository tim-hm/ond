use std::time::Instant;

use serde::Deserialize;
use tokio::sync::mpsc;

use super::super::types::millis;
use super::super::{ModelChunk, ModelError};
use crate::config;

/// Bounds the tool input a stream may assemble.
///
/// The one declared tool's input is a slug and a few small numbers, so a model
/// pouring kilobytes into it is malfunctioning; the accumulated JSON crosses a
/// trust boundary downstream, and an unbounded buffer would let a runaway
/// stream grow it without limit. Crossing the bound drops the tool call and
/// keeps the prose — the same judgement `validate_offer` makes about input it
/// cannot believe.
pub(super) const MAX_TOOL_INPUT_BYTES: usize = 8 * 1024;

#[derive(Default)]
pub(super) struct ToolAssembly {
    /// The open call's name and the input JSON its deltas have delivered.
    open: Option<(String, String)>,
}

impl ToolAssembly {
    pub(super) fn start(&mut self, name: String) {
        if self.open.is_none() {
            self.open = Some((name, String::new()));
        }
    }

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
    /// Text to append to the explanation.
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
    /// A ping, a text block opening, or a usage report — every stream has
    /// several, and none of them is an error.
    Ignored,
}

#[tonic::async_trait]
pub(super) trait EventSource: Send {
    async fn next(&mut self) -> Result<Option<Event>, ModelError>;
}

/// Relays decoded provider events into the model stream.
///
/// The output receiver owns cancellation: once its reader disappears, the
/// provider source is dropped even if it is waiting for another frame. A clean
/// end without text or a tool call is an error because an empty successful RPC
/// leaves the client with a sent message and no answer.
pub(super) async fn relay_events<S: EventSource>(
    mut source: S,
    sender: mpsc::Sender<Result<ModelChunk, ModelError>>,
    mut started: Option<Instant>,
    request_id: Option<&str>,
) {
    let mut answered = false;
    let mut tool = ToolAssembly::default();

    loop {
        let event = tokio::select! {
            event = source.next() => event,
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

fn record_first_chunk(started: &mut Option<Instant>) {
    if let Some(started) = started.take() {
        tracing::info!(
            feature = "assistant",
            model = config::BEDROCK_MODEL_ID,
            duration_ms = millis(started.elapsed()),
            "the model started answering"
        );
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
/// person is reading an explanation, and losing a sentence beats losing the rest
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
        "content_block_start" => frame
            .content_block
            .filter(|block| block.kind == "tool_use")
            .map_or(Event::Ignored, |block| Event::ToolUseStart {
                name: block.name.unwrap_or_default(),
            }),
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
    use std::sync::atomic::{AtomicBool, Ordering};

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
