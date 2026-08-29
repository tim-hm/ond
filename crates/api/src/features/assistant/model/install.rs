//! Which model client this process ends up with. Separate from
//! [`super::types`] on purpose: this is the one file in the seam that must
//! know every implementation by name — a composition root, like `lib.rs` for
//! the router — while the trait it returns stays free of all of them.

use std::sync::Arc;

use super::bedrock::BedrockClient;
use super::breaker::GuardedModelClient;
use super::disabled::DisabledModelClient;
use super::types::ModelClient;
use crate::config::Environment;

/// Installs the model client this process will use. Two outcomes, both
/// normal: AWS credentials resolve — Bedrock behind the breaker — or they do
/// not, and [`DisabledModelClient`] answers every RPC from the rules, flagged
/// `FALLBACK`, which lets a fresh clone and CI run with no AWS identity. The
/// environment is taken only to pick the log level; one line logs either way.
pub async fn install(environment: Environment) -> Arc<dyn ModelClient> {
    // One message, logged at two levels below. `tracing` takes its level as a
    // compile-time constant, so the level cannot be a variable and the two calls
    // cannot share a literal without this.
    const QUIET: &str =
        "the assistant cannot reach Bedrock — answering from the rule-based fallback";

    /// What to do about it, carried only where the reader can act on it.
    /// `mise run dev` pins `AWS_PROFILE=ond-dev`, so a laptop reaching this
    /// line lacks the profile, not a variable — the remedy is the stanza in
    /// docs/contributing.md, not `aws configure`. Production gets no field:
    /// the box signs with an instance profile no shell can configure.
    const REMEDY: &str =
        "add the ond-dev assume-role stanza to ~/.aws/config — docs/contributing.md shows it";

    let error = match BedrockClient::connect().await {
        Ok(client) => {
            // Deliberately not "the assistant is live": a machine that can
            // *sign* for Bedrock is not one authorised to invoke a model — a
            // role missing the grant gets here and then fails every call. So
            // it says what it knows and points at the endpoint that knows more.
            tracing::info!(
                feature = "assistant",
                model = crate::config::BEDROCK_MODEL_ID,
                region = crate::config::BEDROCK_REGION,
                "the assistant will call Bedrock; /about reports whether it answers"
            );
            return Arc::new(GuardedModelClient::new(Arc::new(client)));
        }
        Err(error) => error,
    };

    // On a laptop or a CI runner this is the supported state docs/deployment.md
    // describes; on the box it is the coach being down, and only one of those is
    // worth a `warn`. A match on `Environment` rather than a bool, which is the
    // convention config.rs sets for everything that differs between the two.
    match environment {
        Environment::Production => tracing::warn!(feature = "assistant", %error, "{QUIET}"),
        Environment::Dev => {
            tracing::info!(feature = "assistant", %error, remedy = REMEDY, "{QUIET}");
        }
    }

    Arc::new(DisabledModelClient)
}
