//! Account errors and their gRPC status mapping.

use tonic::Status;

use super::verifier::VerificationError;
use crate::identity::SessionError;

/// Why a sign-in did not bind anything, or an erasure did not erase.
#[derive(Debug, thiserror::Error)]
pub enum AccountError {
    /// The submitted identity token is not one this server will act on —
    /// unparseable, badly signed, issued for another app, or expired. Also
    /// carries the case where Apple's keys could not be fetched, which is this
    /// server's fault rather than the caller's and is separated again on the way
    /// out.
    #[error("{0}")]
    Rejected(#[from] VerificationError),

    /// The client omitted the authorization purpose or sent a value this
    /// server does not know how to constrain.
    #[error("an Apple authorization purpose is required")]
    InvalidPurpose,

    /// No live, single-use challenge matched the signed nonce, caller and
    /// purpose presented by this operation.
    #[error("the Apple authorization challenge is missing, expired, or already used")]
    InvalidChallenge,

    /// Identity tokens are credentials, not an upload surface. Refused before
    /// parsing or key lookup so their memory and CPU cost has a fixed ceiling.
    #[error("the identity token exceeds the {0}-byte limit")]
    TokenTooLarge(usize),

    /// The caller's identity is already bound to a *different* Apple account.
    /// Refused rather than rebound: rebinding would drop the first account's
    /// only route back to its history, which nothing else in the schema
    /// records. An honest client reaches this only by signing in twice without
    /// signing out — a client bug worth surfacing.
    #[error("this installation is already signed in to another Apple account")]
    AlreadyBound,

    /// A deletion arrived for an Apple-bound identity with no identity token on
    /// it. The client is expected to ask Apple for one first; a client that
    /// believes it never signed in reaches this too, and the answer is the same.
    #[error("deleting an account signed in with Apple requires a fresh Apple credential")]
    CredentialRequired,

    /// The identity token is genuinely Apple's but names a *different* Apple
    /// account than the one this identity is bound to. Separate from
    /// [`AccountError::Rejected`] because the credential is fine — somebody
    /// proved an Apple account, just not this one — and "your Apple ID was
    /// rejected" would send a person to re-authenticate as the wrong account.
    #[error("this Apple account is not the one this identity is signed in with")]
    WrongAccount,

    /// The caller's row vanished between the identity layer creating it and this
    /// write. Unreachable short of a manual delete, and surfaced rather than
    /// quietly treated as a first sign-in.
    #[error("no user row for the calling user")]
    Missing,

    /// The operating system could not supply randomness for a challenge.
    #[error("the system random source is unavailable")]
    Randomness,

    /// A session credential could not be minted or persisted. Sign-in keeps
    /// that write in the challenge-and-binding transaction, so this error rolls
    /// the entire authorization back rather than leaving a partial account.
    #[error("{0}")]
    Session(#[from] SessionError),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
}

/// Logs server-side faults before converting: the client only sees an opaque
/// `internal`. A refused token is `UNAUTHENTICATED` — a credential, not a
/// malformed field — and Apple being unreachable is `UNAVAILABLE`, so an
/// outage never reads as a rejection. For erasure: nothing presented is
/// `UNAUTHENTICATED`; a credential proving the wrong account, `PERMISSION_DENIED`.
impl From<AccountError> for Status {
    fn from(error: AccountError) -> Self {
        match &error {
            AccountError::Rejected(VerificationError::Unavailable(e)) => {
                tracing::error!(feature = "account", error = %e, "could not reach Apple's signing keys");
                Self::unavailable("Apple's signing keys are unavailable")
            }
            AccountError::Rejected(e) => {
                // At debug: a rejected token is what a stale credential and a
                // build with the wrong bundle id both produce, and the level
                // should not imply the server is unhealthy.
                tracing::debug!(feature = "account", error = %e, "rejected an identity token");
                Self::unauthenticated(e.to_string())
            }
            AccountError::InvalidPurpose => Self::invalid_argument(error.to_string()),
            AccountError::InvalidChallenge => {
                tracing::debug!(
                    feature = "account",
                    "refused an Apple authorization without a matching live challenge"
                );
                Self::unauthenticated(error.to_string())
            }
            AccountError::TokenTooLarge(limit) => {
                tracing::debug!(
                    feature = "account",
                    limit,
                    "refused an oversized identity token"
                );
                Self::invalid_argument(error.to_string())
            }
            AccountError::CredentialRequired => {
                // At debug beside the rejections above, and for the same reason:
                // a client whose record of having signed in did not survive a
                // reinstall produces this on an honest deletion.
                tracing::debug!(
                    feature = "account",
                    "refused an erasure of an Apple-bound account with no credential"
                );
                Self::unauthenticated(error.to_string())
            }
            AccountError::WrongAccount => {
                // `warn`, unlike the two above: the credential verified, so
                // somebody with a working Apple account asked to erase an
                // identity that is not theirs. Rare, and worth a look.
                tracing::warn!(
                    feature = "account",
                    "refused an erasure proved with another Apple account"
                );
                Self::permission_denied(error.to_string())
            }
            AccountError::AlreadyBound => {
                tracing::warn!(
                    feature = "account",
                    "refused a sign-in on an installation bound to another Apple account"
                );
                Self::failed_precondition(error.to_string())
            }
            AccountError::Missing => {
                tracing::error!(feature = "account", "the calling user has no row");
                Self::internal("internal error")
            }
            AccountError::Randomness => {
                tracing::error!(
                    feature = "account",
                    "could not mint an Apple authorization nonce"
                );
                Self::internal("internal error")
            }
            AccountError::Session(e) => {
                tracing::error!(feature = "account", error = %e, "could not create a session credential");
                Self::internal("internal error")
            }
            AccountError::Database(e) => {
                tracing::error!(feature = "account", error = %e, "database error");
                Self::internal("internal error")
            }
        }
    }
}
