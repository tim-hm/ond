//! What the coach costs and how often it is actually the coach answering.
//! This feature's failure mode is a success: every declining step hands over
//! to `super::fallback` and the call completes with gRPC status 0, so a total
//! provider outage looks identical to a working system on every request
//! metric — the only trace was a `warn` line nothing aggregates.

use std::time::Duration;

use metrics::{counter, gauge, histogram};

use super::model::AssistantMode;

/// Why a rule-based answer was given instead of a model's. Split finer than
/// `service::Claim`, which collapses three situations into `Unavailable`
/// because the caller acts the same in all three — right for control flow,
/// wrong for a metric: an operator needs "the provider is down" separated
/// from "this person has used their allowance".
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

/// The rules wrote it instead, and why. Two metrics because they answer
/// different questions: the alert needs a share of all answers — the same
/// denominator `answered` increments — while diagnosis needs the reason,
/// which would put seven labels on that denominator for no gain.
pub fn fell_back(reason: Fallback) {
    counter!("ond_assistant_answers_total", "source" => "fallback").increment(1);
    counter!("ond_assistant_fallbacks_total", "reason" => reason.as_label()).increment(1);
}

/// What a completed provider call was billed for — nothing else in the
/// process records what the assistant costs, and a counter can be summed over
/// a month where a log line cannot. The four kinds are disjoint and all four
/// price a call: Bedrock bills cache reads below the base rate and cache
/// writes at 1.25×, so folding either into `prompt` would misstate the bill.
pub fn tokens(prompt: u32, completion: u32, cached: u32, cache_written: u32) {
    counter!("ond_assistant_tokens_total", "kind" => "prompt").increment(u64::from(prompt));
    counter!("ond_assistant_tokens_total", "kind" => "completion").increment(u64::from(completion));
    counter!("ond_assistant_tokens_total", "kind" => "cached").increment(u64::from(cached));
    counter!("ond_assistant_tokens_total", "kind" => "cache_write")
        .increment(u64::from(cache_written));
}

/// How long a completed non-streaming call took.
pub fn call_duration(elapsed: Duration) {
    histogram!("ond_assistant_call_duration_seconds").record(elapsed.as_secs_f64());
}

/// How long a streaming call took to produce anything a reader could see —
/// the number `ond_grpc_request_duration_seconds` cannot hold: that measures
/// to the response head, which for a server stream is the handler returning
/// the stream rather than the coach starting to speak.
pub fn time_to_first_token(elapsed: Duration) {
    histogram!("ond_assistant_time_to_first_token_seconds").record(elapsed.as_secs_f64());
}

/// Publishes where a reply would come from right now, as one series per mode.
/// State-set shape — every label present, one of them 1 — because a gauge
/// holding an enum discriminant needs a lookup table off the dashboard, and
/// reordering the enum silently changes historical samples. This is also the
/// breaker's state: [`AssistantMode::Interrupted`] is "the breaker is open".
pub fn set_mode(mode: AssistantMode) {
    for known in AssistantMode::ALL {
        gauge!("ond_assistant_mode", "mode" => known.as_str())
            .set(f64::from(u8::from(known == mode)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pins every label string an alert or dashboard matches on:
    /// `check:metrics` compares metric *names* and `promtool test rules` runs
    /// against fabricated series, so nothing notices a renamed label value —
    /// renaming `allowance_spent` would quietly drop it from
    /// `AssistantFallingBack`'s exclusion and fire an outage alert.
    #[test]
    fn every_fallback_reason_keeps_the_label_the_alerts_match_on() {
        assert_eq!(
            Fallback::SubscriptionRequired.as_label(),
            "subscription_required"
        );
        assert_eq!(Fallback::AllowanceSpent.as_label(), "allowance_spent");
        assert_eq!(
            Fallback::ProviderUnavailable.as_label(),
            "provider_unavailable"
        );
        assert_eq!(Fallback::ClaimFailed.as_label(), "claim_failed");
        assert_eq!(Fallback::ModelError.as_label(), "model_error");
        assert_eq!(Fallback::StreamFailed.as_label(), "stream_failed");
        assert_eq!(Fallback::NoTechnique.as_label(), "no_technique");
    }
}
