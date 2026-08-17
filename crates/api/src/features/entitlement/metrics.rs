//! The census, and what happens to submitted purchases.
//!
//! Two kinds of number and both belong to this feature, for the reason
//! docs/observability.md gives: who counts as subscribed is defined once, here,
//! and a second definition written in an exporter's SQL is one free to disagree
//! with the gate the app enforces.
//!
//! The verification counters are newer and exist because this path was the
//! darkest in the deployment despite being the one that carries money. Every
//! refusal is logged at `debug`, which the production filter drops, and returns
//! gRPC 3 or 7 — both of which `GrpcUnexpectedFailures` excludes on purpose,
//! because both are ordinary. So a signing-chain regression that rejected every
//! genuine Apple transaction would have produced no log line, no metric and no
//! alert, and the only visible symptom would have been `ond_active_subscriptions`
//! failing to rise: a gauge nothing watches, whose flatness is indistinguishable
//! from a quiet week.
//!
//! The levels stay where they are. `debug` is right for a single rejection — a
//! sandbox build talking to a production server produces them all day — and a
//! counter is the correct instrument for a *rate*, which is the thing that is
//! actually alarming.

use metrics::{counter, gauge};
use sqlx::PgPool;

use super::cache::CensusCache;
use super::types::SubscriptionTier;

/// What became of one submitted App Store transaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verification {
    /// Verified and stored. The subscription is live.
    Honoured,
    /// Verified, and Apple says it has been refunded or revoked: stored, and the
    /// entitlement taken away. Separate from [`Self::Honoured`] because it used to
    /// share it, so every refund also incremented the purchase counter — a
    /// dashboard where cancellations read as sales. It is also the only way to ask
    /// "is anyone giving this back", which nothing else answers.
    Revoked,
    /// Apple's signature did not check out, or the payload was not what the
    /// verifier expects. **The one worth alerting on as a share** — a handful
    /// is a beta tester on a sandbox build, and a sustained fraction is the
    /// money path broken for everybody.
    Rejected,
    /// The payload exceeded the size bound before it was ever parsed.
    TooLarge,
    /// The transaction is already bound to a different identity.
    Claimed,
    /// A gated RPC reached by a caller who has not paid. Ordinary, and by far
    /// the most common — kept separate so it cannot drown the rest.
    Unentitled,
    /// The caller has no row, or the database refused. A server fault that
    /// happens to arrive through this feature.
    Faulted,
}

impl Verification {
    const fn as_label(self) -> &'static str {
        match self {
            Self::Honoured => "honoured",
            Self::Revoked => "revoked",
            Self::Rejected => "rejected",
            Self::TooLarge => "too_large",
            Self::Claimed => "claimed",
            Self::Unentitled => "unentitled",
            Self::Faulted => "faulted",
        }
    }
}

/// Records one outcome on the purchase path.
pub fn verification(outcome: Verification) {
    counter!("ond_entitlement_verifications_total", "outcome" => outcome.as_label()).increment(1);
}

/// Records why a submitted transaction was rejected.
///
/// A counter of its own rather than a second label on the outcome above, because
/// a `reason` there would be a label every other outcome had no value for — and
/// one metric name emitting two different label sets is the shape that makes a
/// query's sum quietly wrong. `reason` comes from `VerificationError::kind`,
/// which is where the closed-set argument for it lives.
pub fn rejection(reason: &'static str) {
    counter!("ond_entitlement_rejections_total", "reason" => reason).increment(1);
}

/// Records which App Store environment signed a transaction that was honoured.
///
/// Separate from the outcome because it answers a different question, and one
/// worth being able to ask: a `TestFlight` build points at the production API and
/// transacts in Sandbox, so sandbox purchases are honoured here deliberately.
/// Being able to see the split is what makes "are these real subscribers" a
/// question with an answer rather than an assumption.
pub fn honoured_environment(environment: &'static str) {
    counter!("ond_entitlement_purchases_total", "environment" => environment).increment(1);
}

/// Refreshes the population gauges for one scrape.
///
/// Derived on demand and reused for a minute by the single-flight cache, so
/// four ordinary fifteen-second scrapes share one scan of `users`.
///
/// Takes the two things it reads rather than `AppState`, so the call site says
/// what a census costs; `docs/code-structure.md` reserves `Arc<AppState>` for
/// handlers for the same reason.
///
/// A database that stops answering — or one too slow to answer inside the
/// cache's budget — reports `NaN` rather than the last good reading: a gauge
/// that keeps serving a number it can no longer verify makes the dashboard look
/// healthiest exactly when Postgres has stopped.
#[allow(
    clippy::cast_precision_loss,
    reason = "a population past f64's 53-bit mantissa is 9 quadrillion rows; Prometheus gauges are f64"
)]
pub async fn refresh(census: &CensusCache, pool: &PgPool) {
    let snapshot = census.get(pool).await;

    // `debug`, and the level is the point: this runs once per scrape, so a warn
    // here is one standing condition restated every fifteen seconds for as long
    // as it lasts — the pattern docs/observability.md names as the way people
    // learn to ignore warnings. The condition is not lost. The gauges below go
    // `NaN`, which is what the dashboard reads, and DatabaseUnreachable is the
    // rule that pages.
    if snapshot.refresh_timed_out {
        tracing::debug!(
            "census did not answer within its budget; reporting the product gauges as unknown"
        );
    }
    if let Some(error) = snapshot.refresh_error {
        tracing::debug!(%error, "census unavailable; reporting the product gauges as unknown");
    }

    let (users, plus, mrr) = match snapshot.census {
        Some(census) => (
            census.users as f64,
            census.plus as f64,
            census.gross_mrr_usd,
        ),
        None => (f64::NAN, f64::NAN, f64::NAN),
    };

    gauge!("ond_users_total").set(users);
    gauge!("ond_active_subscriptions", "tier" => SubscriptionTier::Plus.as_metric_label())
        .set(plus);
    gauge!("ond_gross_mrr_usd").set(mrr);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pins every label string an alert or a dashboard query matches on.
    ///
    /// `PurchasesBeingRejected` divides `rejected` by `rejected|honoured`, so a
    /// rename on either side leaves the rule syntactically valid, permanently
    /// zero, and unable to fire — which reads exactly like a healthy money
    /// path. Neither `check:metrics` nor `promtool` can see it.
    #[test]
    fn every_verification_outcome_keeps_the_label_the_alerts_match_on() {
        assert_eq!(Verification::Honoured.as_label(), "honoured");
        assert_eq!(Verification::Rejected.as_label(), "rejected");
        assert_eq!(Verification::TooLarge.as_label(), "too_large");
        assert_eq!(Verification::Claimed.as_label(), "claimed");
        assert_eq!(Verification::Unentitled.as_label(), "unentitled");
        assert_eq!(Verification::Faulted.as_label(), "faulted");
    }
}
