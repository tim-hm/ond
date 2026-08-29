//! What a model client *is* — the trait the whole feature is written against,
//! and the vocabulary its calls are made of. Knows of no implementation:
//! `bedrock`, `breaker` and `disabled` depend on this file and nothing here
//! depends on them, which keeps the dependency arrow one way. The vocabulary
//! is not a provider's; how it becomes a Messages call is `bedrock`'s business.

use std::pin::Pin;
use std::time::Duration;

use tokio_stream::Stream;

/// A reply arriving a piece at a time, in order.
///
/// Boxed rather than an associated type because the trait is used through
/// `dyn`: the composition root chooses the implementation at startup, so the
/// concrete stream type is not known at any call site.
pub type ModelStream = Pin<Box<dyn Stream<Item = Result<ModelChunk, ModelError>> + Send>>;

/// One piece of a streamed reply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelChunk {
    /// Text to append to what came before.
    Text(String),

    /// A completed tool call: the name the provider reported and the input its
    /// deltas assembled, as raw JSON. Unparsed here on purpose — this seam
    /// carries what the model said, and believing any of it is
    /// `super::super::tools`' job.
    ToolUse { name: String, input_json: String },
}

/// Who spoke one turn of a conversation, in the seam's own vocabulary.
///
/// Two variants and no "unspecified": a wire turn that does not name its
/// speaker is rejected at the boundary, so nothing behind it has to carry the
/// doubt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatRole {
    /// The person using the app.
    Person,
    /// The coach's own earlier reply, read back to it.
    Coach,
}

/// One turn of a conversation, ready for a provider to render as genuinely
/// attributed speech. Real roles rather than a transcript serialised into the
/// instruction: an instruction smuggled into a turn arrives marked as
/// somebody's speech, not the caller's authority — harder to inject through.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatTurn {
    pub role: ChatRole,
    pub text: String,
}

/// One call's worth of prompt, split where the cache boundary goes.
pub struct ModelRequest {
    /// Everything identical from one call to the next — the system prompt and
    /// the serialized catalogue. Held separately because the provider caches
    /// this prefix and bills a fraction for it on subsequent calls, and a
    /// prefix that varied per request would never be read back.
    pub cacheable_prefix: String,

    /// The part that differs per caller: their profile, or the technique they
    /// asked about. Always after the prefix, for the same reason.
    pub instruction: String,

    /// The conversation, oldest first, ending on the person's newest message.
    /// Empty for the one-shot RPCs, whose whole ask fits in `instruction`.
    pub turns: Vec<ChatTurn>,

    /// Tools the model may call alongside its prose. Empty for the one-shot
    /// RPCs. Every spec here must be byte-stable across calls: the provider's
    /// cache hierarchy puts tools ahead of the system prompt, so a schema that
    /// varied per request would invalidate the cached prefix on every call.
    pub tools: Vec<ToolSpec>,

    /// The output ceiling. Small on purpose — every response here is a handful
    /// of sentences, and a ceiling is the only cost control that binds even
    /// when the prompt does not.
    pub max_tokens: i32,
}

/// One tool a request declares, in the seam's own vocabulary — a name, what to
/// use it for, and a JSON schema for its input. Provider-neutral on the same
/// terms as the rest of [`ModelRequest`]; how it becomes a Messages API `tools`
/// entry is `super::bedrock`'s business.
#[derive(Debug, Clone)]
pub struct ToolSpec {
    pub name: &'static str,
    pub description: &'static str,
    pub input_schema: serde_json::Value,
}

/// Why a model call did not produce an answer. Two variants because the
/// breaker must tell its own refusals from real failures: counting an
/// `Unavailable` as another failure would keep re-arming the open breaker,
/// and it would never close.
#[derive(Debug, thiserror::Error)]
pub enum ModelError {
    /// The call was never attempted — the breaker is open.
    #[error("the model is not being called: {0}")]
    Unavailable(String),

    /// The call was attempted and failed: unreachable, throttled, refused, or
    /// malformed. Counts against the breaker.
    #[error("the model call failed: {0}")]
    Failed(String),
}

impl ModelError {
    /// The answer a client gives when it declines to call anything.
    ///
    /// One constructor rather than one per implementation, so "the disabled
    /// client answers exactly what the breaker answers" is a fact about the
    /// code rather than a claim in a comment.
    pub fn unavailable(reason: &str) -> Self {
        Self::Unavailable(reason.to_owned())
    }
}

/// Where the assistant's replies come from, as `/about` publishes it. Every
/// state derives from what calls *did*, never from configuration —
/// [`AssistantMode::Live`] is produced only by the breaker, on a call that
/// succeeded. Four states, not a boolean: a tripped breaker recovers alone, a
/// credential-less boot needs a restart, and `Untried` keeps "installed" honest.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AssistantMode {
    /// The provider has answered in this process. The only state that is
    /// evidence rather than intent, and the only one no configuration can
    /// produce on its own.
    Live,
    /// A model is installed and calls are being attempted, but none has
    /// succeeded yet. Nothing is wrong; nothing is proven either.
    Untried,
    /// A model is installed and its breaker is open: recent calls failed, and
    /// the rules answer until the cooldown elapses.
    Interrupted,
    /// No model is installed — this machine could not sign for one at boot, so
    /// the rules answer until it restarts.
    Fallback,
}

impl AssistantMode {
    /// Every mode, for callers that must enumerate rather than match:
    /// `set_mode` has to zero the gauge series that no longer hold, or a
    /// recovered provider would still read as interrupted. Kept beside the
    /// enum so adding a variant cannot miss it.
    pub const ALL: [Self; 4] = [Self::Live, Self::Untried, Self::Interrupted, Self::Fallback];

    /// The name `/about` publishes, as `Environment::as_str` does for the other
    /// thing that endpoint reports.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Live => "live",
            Self::Untried => "untried",
            Self::Interrupted => "interrupted",
            Self::Fallback => "fallback",
        }
    }
}

/// What the assistant needs from a language model, and nothing else.
///
/// `tonic::async_trait` rather than a native `async fn`: async functions in
/// traits are not `dyn`-compatible, and this trait exists to be used through
/// `dyn`. tonic re-exports the macro, so this costs no dependency.
#[tonic::async_trait]
pub trait ModelClient: Send + Sync {
    /// The whole reply, once. Used where the answer is parsed before anyone
    /// sees it — a ranked list is not useful half-arrived.
    async fn complete(&self, request: &ModelRequest) -> Result<String, ModelError>;

    /// The reply as it is written. The `Result` is the call being *established*;
    /// a failure after the first chunk arrives on the stream instead.
    async fn stream(&self, request: &ModelRequest) -> Result<ModelStream, ModelError>;

    /// Where a reply would come from right now. Defaulted to
    /// [`AssistantMode::Untried`], not `Live` — the load-bearing choice here:
    /// a client knows what it is *willing* to do, and only the breaker sees
    /// how calls turn out, so defaulting to `Live` would let a correctly
    /// configured provider report success it never had.
    fn mode(&self) -> AssistantMode {
        AssistantMode::Untried
    }

    /// Whether a call would be attempted at all, asked before one is
    /// prepared. Advisory only — `complete` and `stream` still refuse, since
    /// the breaker can trip in between; it saves the quota claim and prompt a
    /// refusal would waste. Derived from [`Self::mode`] so `/about` and the
    /// decision cannot disagree: implementations override `mode`, never this.
    fn is_available(&self) -> bool {
        matches!(self.mode(), AssistantMode::Live | AssistantMode::Untried)
    }
}

/// A duration as the `duration_ms` field `docs/observability.md` fixes by
/// convention. Saturating rather than fallible: a duration too large for a
/// `u64` of milliseconds is a broken clock, and losing the line to it would
/// hide the outage the line was written to explain.
pub(super) fn millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}
