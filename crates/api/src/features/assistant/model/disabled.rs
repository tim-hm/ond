//! The client installed when the AWS credential chain cannot sign for Bedrock.

use super::{AssistantMode, ModelClient, ModelError, ModelRequest, ModelStream};

/// Refuses every call, with the same `Unavailable` the breaker gives.
///
/// Which is the point: missing AWS credentials are not a mode the service knows
/// about. This takes the path a tripped breaker takes, so a fresh clone and CI
/// exercise the fallback that a real outage would.
pub struct DisabledModelClient;

#[tonic::async_trait]
impl ModelClient for DisabledModelClient {
    async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
        Err(ModelError::unavailable("no model is configured"))
    }

    async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
        Err(ModelError::unavailable("no model is configured"))
    }

    /// The rules, and nothing else until this process restarts. Nothing here
    /// can change, so the caller can skip the quota claim and the prompt
    /// outright rather than preparing a call that is certain to be refused.
    fn mode(&self) -> AssistantMode {
        AssistantMode::Fallback
    }
}
