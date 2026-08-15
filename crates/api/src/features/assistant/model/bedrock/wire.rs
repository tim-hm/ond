//! Bedrock Messages API request and response bodies.
//!
//! These private wire types mirror only fields the application sends or reads.
//! The provider's larger schema stays outside the model boundary, and serde
//! attributes preserve the byte shape that prompt caching and toolless calls
//! depend on.

use serde::{Deserialize, Serialize};

use super::super::{ChatRole, ModelError, ModelRequest};

/// The Messages API contract version Bedrock requires in every request body.
pub(super) const ANTHROPIC_VERSION: &str = "bedrock-2023-05-31";

/// Serializes one request body.
pub(super) fn encode(request: &ModelRequest) -> Result<Vec<u8>, ModelError> {
    serde_json::to_vec(&messages_request(request))
        .map_err(|error| ModelError::Failed(format!("the request body did not encode: {error}")))
}

/// Shapes one provider request without serializing it.
///
/// Exposed within the module so tests can inspect role attribution and cache
/// markers directly instead of reverse-engineering the encoded JSON.
pub(super) fn messages_request(request: &ModelRequest) -> MessagesRequest<'_> {
    let mut messages = vec![Message {
        role: "user",
        content: vec![Block {
            kind: "text",
            text: &request.instruction,
            cache_control: None,
        }],
    }];

    // The conversation as genuinely attributed speech: each turn is its own
    // user or assistant message, never a transcript serialised into the
    // instruction. The model treats an assistant message as words it already
    // said, which is what makes an instruction smuggled into one land as
    // somebody's speech rather than as the caller's authority. Consecutive
    // same-role messages are legal here, so the instruction message above and a
    // leading person turn need no glue.
    messages.extend(request.turns.iter().map(|turn| Message {
        role: match turn.role {
            ChatRole::Person => "user",
            ChatRole::Coach => "assistant",
        },
        content: vec![Block {
            kind: "text",
            text: &turn.text,
            cache_control: None,
        }],
    }));

    // The marker on `system` caches everything ahead of it in the provider's
    // hierarchy — tools included — so declaring a tool forks the cache into a
    // with-tools entry and a without, but moves the marker nowhere.
    let tools: Vec<ToolDef<'_>> = request
        .tools
        .iter()
        .map(|tool| ToolDef {
            name: tool.name,
            description: tool.description,
            input_schema: &tool.input_schema,
        })
        .collect();
    let tool_choice = (!tools.is_empty()).then_some(ToolChoice { kind: "auto" });

    MessagesRequest {
        anthropic_version: ANTHROPIC_VERSION,
        max_tokens: request.max_tokens,
        system: vec![Block {
            kind: "text",
            text: &request.cacheable_prefix,
            // Marks everything up to here as the cacheable prefix, which on
            // this model is billed at a fraction on the next call. Bedrock
            // reads the marker itself; nothing else in the body depends on it.
            cache_control: Some(CacheControl { kind: "ephemeral" }),
        }],
        tools,
        tool_choice,
        messages,
    }
}

/// The subset of an Anthropic Messages request this application sends.
#[derive(Serialize)]
pub(super) struct MessagesRequest<'a> {
    anthropic_version: &'static str,
    max_tokens: i32,
    system: Vec<Block<'a>>,
    /// Skipped when empty so a toolless body is byte-identical to what this
    /// file always sent — the one-shot RPCs' bodies must not change shape.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    tools: Vec<ToolDef<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_choice: Option<ToolChoice>,
    messages: Vec<Message<'a>>,
}

/// One declared tool, in the Messages API's own shape.
#[derive(Serialize)]
struct ToolDef<'a> {
    name: &'a str,
    description: &'a str,
    input_schema: &'a serde_json::Value,
}

/// `{"type":"auto"}` — the model decides whether to call anything. Present
/// exactly when tools are declared.
#[derive(Serialize)]
struct ToolChoice {
    #[serde(rename = "type")]
    kind: &'static str,
}

#[derive(Serialize)]
struct Message<'a> {
    role: &'static str,
    content: Vec<Block<'a>>,
}

#[derive(Serialize)]
struct Block<'a> {
    #[serde(rename = "type")]
    kind: &'static str,
    text: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    cache_control: Option<CacheControl>,
}

/// Marks the end of the prefix worth caching.
#[derive(Serialize)]
struct CacheControl {
    #[serde(rename = "type")]
    kind: &'static str,
}

/// The subset of a completed Messages response this application consumes.
#[derive(Deserialize)]
pub(super) struct MessagesResponse {
    /// Content blocks in provider order; non-text blocks remain representable.
    pub(super) content: Vec<ResponseBlock>,
    /// What the call cost. Optional because a reply that omits it is not a
    /// failed call, only an unmeasured one.
    #[serde(default)]
    pub(super) usage: Option<Usage>,
}

/// One block of a finished reply. `text` is absent on any block that is not
/// text, which this request cannot provoke today and a future one might.
#[derive(Deserialize)]
pub(super) struct ResponseBlock {
    /// The text carried by this block, or `None` for another block kind.
    #[serde(default)]
    pub(super) text: Option<String>,
}

/// The token counts behind one call — the safe substitute for logging what was
/// asked and what came back.
// The shared `tokens` suffix is the wire's, not a naming habit: these are
// Anthropic's field names and renaming them would mean three `serde(rename)`
// attributes to say the same thing less directly.
#[allow(clippy::struct_field_names)]
#[derive(Deserialize)]
pub(super) struct Usage {
    /// Tokens read from the request, including any cache-served prefix.
    #[serde(default)]
    pub(super) input_tokens: u32,
    /// Tokens generated for the response.
    #[serde(default)]
    pub(super) output_tokens: u32,
    /// The part of the prefix served from cache, and the only evidence that the
    /// `cache_control` marker above is worth splitting the prompt for.
    #[serde(default)]
    pub(super) cache_read_input_tokens: u32,
    /// Tokens written into the cache, billed at 1.25× the base rate. Charged
    /// whenever the cached prefix changes or its five-minute entry has lapsed,
    /// so a low-traffic coach pays this far more often than a busy one.
    #[serde(default)]
    pub(super) cache_creation_input_tokens: u32,
}
