//! Deterministic model and identity-provider doubles.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use api::account::{
    AuthorizationNonceHash, IdentityTokenVerifier, VerificationError, VerifiedIdentity,
};
use api::assistant::{ModelChunk, ModelClient, ModelError, ModelRequest, ModelStream};

/// One scripted reply: model text followed by any tool calls.
#[derive(Clone)]
pub struct ScriptedReply {
    pub text: String,
    /// The tool calls streamed after the text, each as `(name, input_json)`.
    ///
    /// A list rather than one, because a provider may emit several `tool_use`
    /// blocks in a single reply and the server's one-proposal-per-reply rule is
    /// only testable against a model that tries to break it.
    pub tool_use: Vec<(String, String)>,
}

impl From<String> for ScriptedReply {
    fn from(text: String) -> Self {
        Self {
            text,
            tool_use: Vec::new(),
        }
    }
}

impl ScriptedReply {
    /// A reply that writes `text` and then calls `name` with `input_json`.
    pub fn with_tool(text: &str, name: &str, input_json: &str) -> Self {
        Self {
            text: text.to_owned(),
            tool_use: vec![(name.to_owned(), input_json.to_owned())],
        }
    }

    /// A reply that ends on more than one tool call — a model reaching for two
    /// cards under one paragraph.
    pub fn with_tools(text: &str, calls: &[(&str, &str)]) -> Self {
        Self {
            text: text.to_owned(),
            tool_use: calls
                .iter()
                .map(|(name, input)| ((*name).to_owned(), (*input).to_owned()))
                .collect(),
        }
    }
}

pub struct ScriptedModel {
    /// Replies in order; the last one repeats once the script runs out.
    replies: Mutex<Vec<Result<ScriptedReply, ModelError>>>,
    /// Every request received, in the order the calls arrived.
    requests: Mutex<Vec<ModelRequest>>,
}

impl ScriptedModel {
    /// `next` repeats a sole entry forever, so "always" is a one-element script.
    pub fn always(reply: Result<impl Into<ScriptedReply>, ModelError>) -> Arc<Self> {
        Self::script(vec![reply])
    }

    /// A model that fails every call — `always(Err(…))`, minus the type
    /// annotation an `Err`-only script would otherwise need to name the reply
    /// type it never produces.
    pub fn failing(error: ModelError) -> Arc<Self> {
        Self::script(vec![Err::<ScriptedReply, _>(error)])
    }

    pub fn script(replies: Vec<Result<impl Into<ScriptedReply>, ModelError>>) -> Arc<Self> {
        Arc::new(Self {
            replies: Mutex::new(
                replies
                    .into_iter()
                    .map(|reply| reply.map(Into::into))
                    .collect(),
            ),
            requests: Mutex::new(Vec::new()),
        })
    }

    pub fn calls(&self) -> usize {
        self.lock_requests().len()
    }

    /// What the model was asked, for asserting on the prompt itself.
    ///
    /// Copies rather than a guard, so no lock ever leaves the harness — a held
    /// guard would quietly deadlock the next capture, and a test double two
    /// suites share should not come with a locking rule.
    pub fn requests(&self) -> Vec<ModelRequest> {
        self.lock_requests().iter().map(copy_request).collect()
    }

    fn lock_requests(&self) -> std::sync::MutexGuard<'_, Vec<ModelRequest>> {
        self.requests.lock().expect("the requests are not poisoned")
    }

    fn next(&self, request: &ModelRequest) -> Result<ScriptedReply, ModelError> {
        self.lock_requests().push(copy_request(request));

        let mut replies = self.replies.lock().expect("the script is not poisoned");
        if replies.len() > 1 {
            replies.remove(0)
        } else {
            match replies.first() {
                Some(Ok(reply)) => Ok(reply.clone()),
                Some(Err(_)) | None => Err(ModelError::Failed("scripted failure".to_owned())),
            }
        }
    }
}

/// Field by field because `ModelRequest` does not implement `Clone`, and the
/// production seam should not grow one for a test double's sake.
fn copy_request(request: &ModelRequest) -> ModelRequest {
    ModelRequest {
        cacheable_prefix: request.cacheable_prefix.clone(),
        instruction: request.instruction.clone(),
        turns: request.turns.clone(),
        tools: request.tools.clone(),
        max_tokens: request.max_tokens,
    }
}

#[tonic::async_trait]
impl ModelClient for ScriptedModel {
    async fn complete(&self, request: &ModelRequest) -> Result<String, ModelError> {
        self.next(request).map(|reply| reply.text)
    }

    /// One chunk per line — so a test can assert the client received them in
    /// the order the model wrote them — then the scripted tool call, last,
    /// exactly where the prompt tells the real model to put one.
    async fn stream(&self, request: &ModelRequest) -> Result<ModelStream, ModelError> {
        let reply = self.next(request)?;
        let mut chunks: Vec<Result<ModelChunk, ModelError>> = reply
            .text
            .lines()
            .map(|line| Ok(ModelChunk::Text(line.to_owned())))
            .collect();
        for (name, input_json) in reply.tool_use {
            chunks.push(Ok(ModelChunk::ToolUse { name, input_json }));
        }

        Ok(Box::pin(tokio_stream::iter(chunks)))
    }
}

/// A Sign in with Apple verifier that knows a fixed set of tokens and refuses
/// everything else. Keyed on the token string, so a test can submit "the same
/// credential" twice and mean it. In the harness because every router this
/// file builds needs one: the real verifier fetches Apple's signing keys over
/// the network, and a default that could do that is a suite that fails on a train.
pub struct ScriptedIdentityVerifier {
    /// Token to the Apple account it proves.
    identities: HashMap<String, String>,
}

pub const SCRIPTED_NONCE_SEPARATOR: &str = "::ond-nonce::";

impl ScriptedIdentityVerifier {
    pub fn with(tokens: Vec<(&str, &str)>) -> Arc<Self> {
        Arc::new(Self {
            identities: tokens
                .into_iter()
                .map(|(token, apple_user_id)| (token.to_owned(), apple_user_id.to_owned()))
                .collect(),
        })
    }

    /// The default for every suite that is not about signing in: it refuses
    /// every token, and reaches nothing to do it.
    pub fn refusing() -> Arc<Self> {
        Self::with(vec![])
    }
}

#[tonic::async_trait]
impl IdentityTokenVerifier for ScriptedIdentityVerifier {
    async fn verify(&self, identity_token: &str) -> Result<VerifiedIdentity, VerificationError> {
        let (identity_token, nonce) = identity_token
            .rsplit_once(SCRIPTED_NONCE_SEPARATOR)
            .ok_or_else(|| {
                VerificationError::Malformed("scripted token has no nonce".to_owned())
            })?;
        let authorization_nonce = AuthorizationNonceHash::from_apple_claim(nonce)
            .map_err(|error| VerificationError::Malformed(error.to_string()))?;

        self.identities
            .get(identity_token)
            .map(|apple_user_id| VerifiedIdentity {
                apple_user_id: apple_user_id.clone(),
                authorization_nonce,
            })
            .ok_or_else(|| VerificationError::Untrusted("scripted rejection".to_owned()))
    }
}
