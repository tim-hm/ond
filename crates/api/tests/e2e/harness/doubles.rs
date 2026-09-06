use api::account::{
    AuthorizationNonceHash, IdentityTokenVerifier, VerificationError, VerifiedIdentity,
};
use std::collections::HashMap;
use std::sync::Arc;

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
