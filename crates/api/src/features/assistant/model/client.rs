//! What a model client *is* — the trait the whole feature is written against,
//! and the vocabulary its calls are made of.
//!
//! Deliberately knows of no implementation. `bedrock`, `breaker` and `disabled`
//! all depend on this file and nothing here depends on them, which is what lets
//! quota, validation and fallback be exercised with no network and no
//! credentials. Choosing between the implementations is `super::install`, and
//! keeping that choice out of here is what keeps the dependency arrow pointing
//! one way.
//!
//! The vocabulary is deliberately not a provider's. A [`ModelRequest`] is a
//! cacheable prefix, an instruction, and a ceiling; how that becomes a Messages
//! API call is `super::bedrock`'s business.

use std::pin::Pin;
use std::time::Duration;

use tokio_stream::Stream;

/// Text arriving a piece at a time, in order.
///
/// Boxed rather than an associated type because the trait is used through
/// `dyn`: the composition root chooses the implementation at startup, so the
/// concrete stream type is not known at any call site.
pub type ModelStream = Pin<Box<dyn Stream<Item = Result<String, ModelError>> + Send>>;

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
/// attributed speech.
///
/// Real roles rather than a transcript serialised into the instruction, on
/// purpose: a provider renders these as actual user/assistant messages, and an
/// instruction smuggled into a turn arrives marked as somebody's speech rather
/// than as the caller's authority — materially harder to inject through.
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

    /// The output ceiling. Small on purpose — every response here is a handful
    /// of sentences, and a ceiling is the only cost control that binds even
    /// when the prompt does not.
    pub max_tokens: i32,
}

/// Why a model call did not produce an answer.
///
/// Two variants because the circuit breaker has to tell its own refusals apart
/// from real failures: counting an `Unavailable` as another failure would keep
/// re-arming the breaker for as long as it stayed open, and it would never
/// close.
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

/// Where the assistant's replies are coming from, as `/about` publishes it.
///
/// **Every state here is derived from what calls did, never from what is
/// configured**, and that rule is the whole design. A field reporting "Bedrock"
/// because `config.rs` names Bedrock would be the outage it exists to expose,
/// wearing a new hat: the configuration was right throughout, and the IAM grant
/// behind it was missing. So [`Live`] is produced in exactly one place — the
/// breaker, on a call that actually succeeded — and nothing else can reach it.
///
/// Four states rather than a boolean, because the interesting answers are the
/// ones a boolean collapses. "The rules answered" has two causes with opposite
/// remedies: a provider that just failed repeatedly recovers on its own once
/// the cooldown elapses, while a process that could not sign for one at boot
/// answers from the rules until it is restarted somewhere its credentials work.
/// And "a model is installed" is not the same claim as "the model answers",
/// which is what [`Untried`] keeps honest — credentials that resolve are not
/// credentials that are *authorised*, and a deployment carrying no
/// `bedrock:InvokeModel` grant boots indistinguishably from a working one until
/// something asks it for a reply.
///
/// [`Live`]: AssistantMode::Live
/// [`Untried`]: AssistantMode::Untried
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

    /// Where a reply would come from right now.
    ///
    /// Defaulted to [`AssistantMode::Untried`], not `Live`, and that is the
    /// load-bearing choice in this file. A client knows what it is *willing* to
    /// do; only [`breaker::GuardedModelClient`] sees how calls turn out, so it
    /// is the only implementation that can promote a mode to `Live`. Defaulting
    /// to `Live` would let a correctly configured provider report success it had
    /// never had — which is the failure this enum exists to make impossible,
    /// restated one layer up.
    fn mode(&self) -> AssistantMode {
        AssistantMode::Untried
    }

    /// Whether a call would be attempted at all, asked before one is prepared.
    ///
    /// Purely advisory and deliberately not authoritative — `complete` and
    /// `stream` still refuse on their own, because the breaker can trip between
    /// this answer and the call. What it buys is that the caller can skip the
    /// work a refusal would waste: a quota claim, which is a database write, and
    /// the prompt, which walks the whole catalogue. Where no AWS credentials
    /// resolved that is every request in the process.
    ///
    /// Derived from [`Self::mode`] rather than implemented alongside it, so the
    /// mode `/about` publishes and the decision the service acts on cannot
    /// disagree. Implementations override `mode`; nothing overrides this.
    fn is_available(&self) -> bool {
        matches!(self.mode(), AssistantMode::Live | AssistantMode::Untried)
    }
}

/// A duration as the `duration_ms` field `docs/observability.md` fixes by
/// convention.
///
/// Saturating rather than fallible: a duration too large for a `u64` of
/// milliseconds is a broken clock, and losing the line to it would hide the
/// outage the line was written to explain.
pub(super) fn millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}
