//! What the coach costs and how often it is actually the coach answering.
//!
//! This feature was the largest blind spot in the deployment, and the reason is
//! that its failure mode is a success. Every step that declines hands over to
//! `super::fallback`, the RPC returns a perfectly good rule-based answer, and
//! the call completes with gRPC status 0 — so a total provider outage looks
//! identical to a working system on every request metric, every latency
//! histogram and all four of the original alert rules. The only trace was a
//! `warn` line in a log nothing aggregates.
//!
//! The names live here rather than in `obs::metrics` for the reason
//! docs/observability.md gives for the census: a metric's meaning belongs to the
//! feature that defines it, and `obs` owns recorder mechanics only.

use std::time::Duration;

use metrics::{counter, gauge, histogram};

use super::model::AssistantMode;

/// Why a rule-based answer was given instead of a model's.
///
/// Split finer than the code that produces it. `service::Claim` collapses three
/// situations into `Unavailable` because the caller does the same thing in all
/// three, which is right for control flow and wrong for a metric: an operator
/// needs "the provider is down" separated from "this person has used their
/// allowance", and those two arrive at the same branch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fallback {
    /// The caller's tier buys no model call. Ordinary, and the most common
    /// reason on a free-heavy user base — excluded from the alert for exactly
    /// that reason.
    SubscriptionRequired,
    /// Today's allowance is spent. Also ordinary; also excluded.
    AllowanceSpent,
    /// No model is installed, or its breaker is open. **This is the outage
    /// signal** — the one the alert watches.
    ProviderUnavailable,
    /// The quota row could not be written. A database fault wearing a
    /// fallback's clothes, and worth separating from the outage it resembles.
    ClaimFailed,
    /// The call was made and failed.
    ModelError,
    /// The stream could not be established.
    StreamFailed,
    /// The model answered, and named no technique the catalogue has. Contract
    /// or prompt drift rather than an outage, and it needs its own name because
    /// nothing else distinguishes a bad answer from an absent one.
    NoTechnique,
}

impl Fallback {
    const fn as_label(self) -> &'static str {
        match self {
            Self::SubscriptionRequired => "subscription_required",
            Self::AllowanceSpent => "allowance_spent",
            Self::ProviderUnavailable => "provider_unavailable",
            Self::ClaimFailed => "claim_failed",
            Self::ModelError => "model_error",
            Self::StreamFailed => "stream_failed",
            Self::NoTechnique => "no_technique",
        }
    }
}

/// A model wrote the answer somebody read.
pub fn answered() {
    counter!("ond_assistant_answers_total", "source" => "model").increment(1);
}

/// The rules wrote it instead, and why.
///
/// Two metrics rather than one because they answer different questions and a
/// single one cannot serve both: the alert needs a share of all answers, which
/// wants the same denominator `answered` increments, while diagnosis needs the
/// reason, which would put seven labels on that denominator for no gain.
pub fn fell_back(reason: Fallback) {
    counter!("ond_assistant_answers_total", "source" => "fallback").increment(1);
    counter!("ond_assistant_fallbacks_total", "reason" => reason.as_label()).increment(1);
}

/// What a completed provider call was billed for.
///
/// Recorded beside the `info` line that already reports the same numbers, and
/// for the reason that line gives — nothing else in the process records what
/// the assistant costs. The difference is that a counter can be graphed and
/// summed over a month, and a log line in a file nothing ships cannot.
///
/// `cached` is not a subset of `prompt`: Bedrock reports cache reads separately
/// and prices them lower, so adding them would overstate the bill.
pub fn tokens(prompt: u32, completion: u32, cached: u32) {
    counter!("ond_assistant_tokens_total", "kind" => "prompt").increment(u64::from(prompt));
    counter!("ond_assistant_tokens_total", "kind" => "completion").increment(u64::from(completion));
    counter!("ond_assistant_tokens_total", "kind" => "cached").increment(u64::from(cached));
}

/// How long a completed non-streaming call took.
pub fn call_duration(elapsed: Duration) {
    histogram!("ond_assistant_call_duration_seconds").record(elapsed.as_secs_f64());
}

/// How long a streaming call took to produce anything a reader could see.
///
/// The number that matters for a streamed turn, and the one the transport
/// histogram cannot hold: `ond_grpc_request_duration_seconds` measures to the
/// response head, which for a server stream is the moment the handler returned
/// the stream rather than the moment the coach started speaking.
pub fn time_to_first_token(elapsed: Duration) {
    histogram!("ond_assistant_time_to_first_token_seconds").record(elapsed.as_secs_f64());
}

/// Publishes where a reply would come from right now, as one series per mode.
///
/// The state-set shape — every label present, one of them 1 — rather than a
/// single gauge holding an enum's discriminant. A number that means `2` needs a
/// lookup table living somewhere other than the dashboard, and the first person
/// to reorder the enum silently changes what every historical sample meant.
///
/// This is also the breaker's state, which is why no separate gauge reports it:
/// [`AssistantMode::Interrupted`] is precisely "the breaker is open".
pub fn set_mode(mode: AssistantMode) {
    for known in AssistantMode::ALL {
        gauge!("ond_assistant_mode", "mode" => known.as_str())
            .set(f64::from(u8::from(known == mode)));
    }
}
