//! Who a verified credential names, why one is refused, and the trait that
//! makes both answers. Split out of `mod.rs` per `docs/code-structure.md`,
//! which keeps `mod.rs` to declarations and re-exports.

/// Who the caller proved they are: Apple's account id and the server-issued
/// nonce Apple signed beside it. Email and profile claims are deliberately
/// left behind — nothing here sends mail, and a private-relay address is a
/// fact about Apple's forwarding rather than about the person.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedIdentity {
    /// Apple's `sub`. Stable for one Apple ID against one developer team and
    /// opaque outside it, which is exactly what makes it usable as the key a
    /// person's history is filed under.
    pub apple_user_id: String,

    /// The SHA-256 nonce claim, decoded into the one representation the
    /// challenge repository compares.
    pub authorization_nonce: super::super::authorization::AuthorizationNonceHash,
}

/// Why a submitted identity token proved nothing. The variants mean different
/// things about the caller — a client bug, a forgery, a build pointed at the
/// wrong app — and the message travels, so the distinction is what a client
/// author sees when a sign-in fails.
#[derive(Debug, thiserror::Error)]
pub enum VerificationError {
    /// Not a JWT, or a JWT whose parts do not decode: wrong segment count,
    /// invalid base64url, a header or payload that is not the JSON this expects.
    #[error("the identity token is malformed: {0}")]
    Malformed(String),

    /// The bytes parsed, and the signature is not Apple's — an unknown key id, a
    /// signature that does not verify, an algorithm other than the RS256 Apple
    /// signs with, an issuer that is not Apple, or a token that has expired.
    #[error("the identity token is not a valid Apple credential: {0}")]
    Untrusted(String),

    /// Genuinely Apple's, and issued for somebody else's app. The one rejection
    /// that is nobody's bug: a build whose bundle id does not match the one this
    /// server was compiled for produces exactly this.
    #[error("the identity token is not for this app: {0}")]
    NotOurs(String),

    /// Apple's key endpoint could not be reached or did not answer with a key
    /// set. This server's problem rather than the caller's, and separated from
    /// the three above so it can be logged and reported as such — telling
    /// somebody their credential is invalid when the truth is that we could not
    /// check it would have them re-authenticating against an outage.
    #[error("Apple's signing keys are unavailable: {0}")]
    Unavailable(String),
}

/// What the account feature needs from a credential checker, and nothing else.
/// `tonic::async_trait` rather than a native `async fn`, matching
/// `assistant::model::ModelClient`: async trait functions are not
/// `dyn`-compatible, and this is used through `dyn` so the composition root
/// picks the implementation and no test can reach Apple by accident.
#[tonic::async_trait]
pub trait IdentityTokenVerifier: Send + Sync {
    /// Checks `identity_token` and returns the Apple account it names. Every
    /// check lives here, for the reason `TransactionVerifier::verify` gives:
    /// "verified" must mean one thing — Apple signed it, for this app, and it
    /// has not expired. A service that had to remember the audience check
    /// afterwards would eventually forget, and the failure would be silent.
    async fn verify(&self, identity_token: &str) -> Result<VerifiedIdentity, VerificationError>;
}

/// Folds a take-apart failure into the malformed arm.
impl From<crate::jws::MalformedJws> for VerificationError {
    fn from(error: crate::jws::MalformedJws) -> Self {
        Self::Malformed(error.0)
    }
}
