//! The real [`ModelClient`]: Anthropic's Messages API, served by Amazon Bedrock.
//!
//! The only file in this feature that knows a provider exists. Everything above
//! it — quota, breaker, validation, fallback — is written against the trait in
//! `super::model`, so changing provider is this file and two constants in
//! `config.rs`.
//!
//! Bedrock is called directly rather than through an intermediary, which is the
//! whole point of the arrangement: no third party sees a person's words in
//! transit, and `web/privacy.html` can name exactly one processor. The call is
//! signed with the EC2 instance profile that `infra/main.tf` already attaches,
//! found through the AWS SDK's default credential chain — so there is no key on
//! the box and no environment variable naming one.
//!
//! Two things about the request body are Bedrock's rather than Anthropic's: the
//! model is named in the URL instead of the body, and `anthropic_version`
//! replaces it there. Everything else is the Messages API as documented,
//! `cache_control` included — it marks the end of the prefix Bedrock caches,
//! and it is why `ModelRequest` splits the prompt in two rather than handing
//! over one string.

mod client;
mod events;
mod wire;

pub use self::client::BedrockClient;

#[cfg(test)]
use self::events::{Event, MAX_TOOL_INPUT_BYTES, ToolAssembly, parse_event, refused};
#[cfg(test)]
use self::wire::{ANTHROPIC_VERSION, messages_request};
#[cfg(test)]
use super::{ChatRole, ModelChunk, ModelRequest};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::assistant::model::ChatTurn;

    fn request() -> ModelRequest {
        ModelRequest {
            cacheable_prefix: "the catalogue".to_owned(),
            instruction: "a profile".to_owned(),
            turns: vec![],
            tools: vec![],
            max_tokens: 64,
        }
    }

    fn tool() -> super::super::ToolSpec {
        super::super::ToolSpec {
            name: "offer_exercise",
            description: "offer one exercise",
            input_schema: serde_json::json!({ "type": "object" }),
        }
    }

    /// The two ways this body differs from the Messages API as published, and
    /// both are absolute: Bedrock rejects a body without `anthropic_version`,
    /// and rejects one carrying `model` — which it reads from the URL. Pinned on
    /// the serialised JSON because that is what leaves the process.
    #[test]
    fn the_body_is_the_bedrock_messages_shape() {
        let body = serde_json::to_value(messages_request(&request()))
            .expect("the request body serialises");

        assert_eq!(body["anthropic_version"], ANTHROPIC_VERSION);
        assert_eq!(body["max_tokens"], 64);
        assert!(
            body.get("model").is_none(),
            "the model is named in the URL, and a `model` here is rejected: {body}"
        );
    }

    /// Dropped or misplaced, the marker fails open: the call simply runs
    /// uncached, nothing reports it, and the only sign is the bill. It belongs
    /// on the system prefix and nowhere else — a marker on a per-caller message
    /// writes a cache entry that is never read back.
    #[test]
    fn only_the_cacheable_prefix_is_marked() {
        let body = serde_json::to_value(messages_request(&request()))
            .expect("the request body serialises");

        assert_eq!(
            body["system"][0]["cache_control"],
            serde_json::json!({ "type": "ephemeral" })
        );
        assert_eq!(body["system"][0]["text"], "the catalogue");
        assert!(
            body["messages"][0].get("cache_control").is_none(),
            "the instruction differs per caller and must not be marked: {body}"
        );
    }

    /// The conversation reaches the model as real speech rather than a
    /// transcript, which is what makes an instruction inside a turn arrive as
    /// somebody's words instead of the caller's authority.
    #[test]
    fn turns_are_attributed_messages() {
        let mut request = request();
        request.turns = vec![
            ChatTurn {
                role: ChatRole::Person,
                text: "I wake at 3am.".to_owned(),
            },
            ChatTurn {
                role: ChatRole::Coach,
                text: "Try a longer exhale.".to_owned(),
            },
        ];

        let body =
            serde_json::to_value(messages_request(&request)).expect("the request body serialises");

        assert_eq!(body["messages"][0]["role"], "user");
        assert_eq!(body["messages"][0]["content"][0]["text"], "a profile");
        assert_eq!(body["messages"][1]["role"], "user");
        assert_eq!(body["messages"][2]["role"], "assistant");
    }

    /// A toolless body must not change shape: the one-shot RPCs declare no
    /// tools, and a `tools: []` or `tool_choice: null` riding along would be a
    /// different byte sequence against the provider's cache for no reason.
    #[test]
    fn a_toolless_body_carries_no_tool_fields() {
        let body = serde_json::to_value(messages_request(&request()))
            .expect("the request body serialises");

        assert!(body.get("tools").is_none(), "{body}");
        assert!(body.get("tool_choice").is_none(), "{body}");
    }

    /// A declared tool rides the wire in the Messages API's own shape, the
    /// model keeps the choice, and the cache marker stays exactly where it was
    /// — on the system prefix, nowhere else.
    #[test]
    fn a_declared_tool_rides_the_wire_shape() {
        let mut request = request();
        request.tools = vec![tool()];

        let body =
            serde_json::to_value(messages_request(&request)).expect("the request body serialises");

        assert_eq!(body["tools"][0]["name"], "offer_exercise");
        assert_eq!(body["tools"][0]["description"], "offer one exercise");
        assert_eq!(
            body["tools"][0]["input_schema"],
            serde_json::json!({ "type": "object" })
        );
        assert_eq!(body["tool_choice"], serde_json::json!({ "type": "auto" }));
        assert_eq!(
            body["system"][0]["cache_control"],
            serde_json::json!({ "type": "ephemeral" })
        );
        assert!(body["tools"][0].get("cache_control").is_none(), "{body}");
    }

    /// The tool-use frames: the block opening names the tool, its input arrives
    /// as `input_json_delta` fragments, and the block closing is what says the
    /// input is complete.
    #[test]
    fn tool_use_frames_are_recognised() {
        let Event::ToolUseStart { name } = parse_event(
            br#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"offer_exercise"}}"#,
        ) else {
            panic!("a tool_use block start opens a tool call");
        };
        assert_eq!(name, "offer_exercise");

        let Event::ToolInputDelta(json) = parse_event(
            br#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"technique_"}}"#,
        ) else {
            panic!("an input_json_delta is a tool input fragment");
        };
        assert_eq!(json, "{\"technique_");

        assert!(matches!(
            parse_event(br#"{"type":"content_block_stop","index":1}"#),
            Event::BlockStop
        ));
    }

    /// A provider framing fault must not open the tool accumulator under an
    /// empty name and occupy the reply's one-proposal latch.
    #[test]
    fn a_nameless_tool_start_is_ignored() {
        assert!(matches!(
            parse_event(
                br#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1"}}"#
            ),
            Event::Ignored
        ));
        assert!(matches!(
            parse_event(
                br#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":""}}"#
            ),
            Event::Ignored
        ));
    }

    /// The three shapes every stream carries, and the ones that must not be
    /// mistaken for text: a block boundary and a ping arrive on every stream.
    /// A *text* block's opening stays ignored — only `tool_use` opens anything.
    #[test]
    fn only_content_deltas_become_text() {
        assert!(matches!(
            parse_event(br#"{"type":"message_stop"}"#),
            Event::Done
        ));
        assert!(matches!(parse_event(br#"{"type":"ping"}"#), Event::Ignored));
        assert!(matches!(
            parse_event(br#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
            Event::Ignored
        ));
        // Usage frames used to be ignored, which is why the streaming path —
        // the one chat uses — reported no token cost at all. Both halves of the
        // bill are now read: the prompt and any cache read when the message
        // opens, the completion when it closes.
        assert!(matches!(
            parse_event(br#"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}"#),
            Event::Usage { prompt: 0, completion: 9, cached: 0 }
        ));
        assert!(matches!(
            parse_event(br#"{"type":"message_start","message":{"usage":{"input_tokens":11,"cache_read_input_tokens":7}}}"#),
            Event::Usage { prompt: 11, completion: 0, cached: 7 }
        ));
        // A message_start without a usage block is still not an error.
        assert!(matches!(
            parse_event(br#"{"type":"message_start","message":{}}"#),
            Event::Ignored
        ));

        let Event::Text(text) = parse_event(
            br#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"a long"}}"#,
        ) else {
            panic!("a content delta is text");
        };
        assert_eq!(text, "a long");
    }

    /// A malformed frame is skipped rather than failing the stream: the person
    /// is reading a reply, and losing a sentence beats losing the rest
    /// of it.
    #[test]
    fn a_malformed_frame_is_skipped() {
        assert!(matches!(parse_event(b"{not json"), Event::Ignored));
    }

    /// How a throttle or an upstream outage arrives once the response has
    /// already committed to a 200. Read as `Ignored` this decodes as a stream
    /// that simply stopped, which the caller cannot tell from a finished answer.
    #[test]
    fn a_mid_stream_error_frame_fails_the_stream() {
        let Event::Failed(kind) = parse_event(
            br#"{"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}"#,
        ) else {
            panic!("an error frame fails the stream");
        };
        assert_eq!(kind.as_deref(), Some("overloaded_error"));

        assert!(matches!(
            parse_event(br#"{"type":"error","error":{"message":"unwell"}}"#),
            Event::Failed(None)
        ));
    }

    /// A tool call assembles across deltas and completes only on the block
    /// boundary. A nameless start and a boundary with nothing open both emit
    /// nothing, so neither can block the next real call.
    #[test]
    fn a_tool_call_assembles_across_deltas() {
        let mut tool = ToolAssembly::default();
        assert!(tool.finish().is_none(), "a text block's stop emits nothing");

        tool.start(String::new());
        tool.start("offer_exercise".to_owned());
        tool.append("{\"technique_slug\":");
        tool.append("\"box-breathing\"}");

        assert_eq!(
            tool.finish(),
            Some(ModelChunk::ToolUse {
                name: "offer_exercise".to_owned(),
                input_json: "{\"technique_slug\":\"box-breathing\"}".to_owned(),
            })
        );
    }

    /// Input crossing the bound drops the whole call rather than truncating
    /// it: truncated JSON would parse as garbage downstream, and the prose the
    /// model wrote alongside it is still worth delivering.
    #[test]
    fn oversized_tool_input_drops_the_call() {
        let mut tool = ToolAssembly::default();
        tool.start("offer_exercise".to_owned());
        tool.append(&"x".repeat(MAX_TOOL_INPUT_BYTES));
        tool.append("y");

        assert!(tool.finish().is_none());
    }

    /// A moderation refusal quotes the input back in `message`, so neither the
    /// error string nor anything derived from it may carry that field. The type
    /// is the whole reportable part.
    #[test]
    fn a_reported_failure_never_carries_provider_prose() {
        let Event::Failed(kind) = parse_event(
            br#"{"type":"error","error":{"type":"invalid_request_error","message":"flagged: my private words"}}"#,
        ) else {
            panic!("an error frame fails the stream");
        };

        let reported = refused("the provider failed mid-stream", kind.as_deref(), None).to_string();
        assert!(reported.contains("invalid_request_error"));
        assert!(!reported.contains("my private words"), "{reported}");
    }
}
