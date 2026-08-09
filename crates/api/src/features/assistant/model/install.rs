//! Which model client this process ends up with.
//!
//! Separate from [`super::types`] on purpose: this is the one file in the seam
//! that has to know every implementation by name, and the seam's whole value is
//! that nothing else does. It is a composition root — the same job `lib.rs`
//! does for the router — so it reaches for `bedrock`, `breaker`, `disabled` and
//! the environment, while the trait it returns stays free of all four.

use std::sync::Arc;

use super::bedrock::BedrockClient;
use super::breaker::GuardedModelClient;
use super::disabled::DisabledModelClient;
use super::types::ModelClient;
use crate::config::Environment;

/// Installs the model client this process will use.
///
/// Two outcomes, and both are normal:
///
/// - **AWS credentials resolve** — Bedrock, behind the circuit breaker. On the
///   box those credentials are the instance profile, reached over the metadata
///   endpoint; on a developer's machine they are the `ond-dev` profile `mise
///   run dev` pins — an assumed role carrying the box's own invoke-model
///   policy.
/// - **They do not** — [`DisabledModelClient`], which is not a degraded mode so
///   much as the app's offline-first promise applied at boot: every RPC still
///   answers, from the rules, flagged `FALLBACK`. That is what lets a fresh
///   clone run `mise run dev` and the integration tests run in CI with no AWS
///   identity at all.
///
/// Nothing about *which* model is configurable — region and model are
/// constants, and the credentials are found rather than supplied. The
/// environment is taken for one reason, which is the level the second outcome is
/// logged at: on a laptop or a CI runner it is the supported state this repo
/// documents, and on the box the same line means the coach is down. Async only
/// because finding credentials is.
///
/// One log line either way, because "the assistant is quiet today" is otherwise
/// indistinguishable from "this machine cannot sign for Bedrock" from outside
/// the process.
pub async fn install(environment: Environment) -> Arc<dyn ModelClient> {
    // One message, logged at two levels below. `tracing` takes its level as a
    // compile-time constant, so the level cannot be a variable and the two calls
    // cannot share a literal without this.
    const QUIET: &str =
        "the assistant cannot reach Bedrock — answering from the rule-based fallback";

    /// What to do about it, carried only where the reader can act on it.
    ///
    /// `mise run dev` pins `AWS_PROFILE=ond-dev`, so a laptop that still
    /// reaches this line has no such profile rather than a forgotten variable —
    /// the remedy is the stanza docs/contributing.md shows, not `aws
    /// configure`, which would mint keys for a profile that holds none.
    /// Production gets no such field: the box signs with an instance profile
    /// nobody can configure from a shell, so a command here would be a wrong
    /// answer printed with confidence.
    const REMEDY: &str =
        "add the ond-dev assume-role stanza to ~/.aws/config — docs/contributing.md shows it";

    let error = match BedrockClient::connect().await {
        Ok(client) => {
            // Deliberately not "the assistant is live". This line is reached by
            // a machine that can *sign* for Bedrock, which is not the same as
            // one that is authorised to invoke a model — a role missing the
            // grant gets here and then fails every call. Claiming live here is
            // the log-side version of exactly the mistake `AssistantMode`
            // exists to avoid, so it says what it knows and points at the
            // endpoint that knows the rest.
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
