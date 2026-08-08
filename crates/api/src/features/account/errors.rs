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

    /// The caller's identity is already bound to a *different* Apple account.
    ///
    /// Refused rather than rebound, because rebinding would drop the first
    /// account's only route back to that history — nothing else in the schema
    /// records it. An honest client reaches this only by signing in twice
    /// without signing out in between, which is a client bug worth surfacing.
    #[error("this installation is already signed in to another Apple account")]
    AlreadyBound,

    /// A deletion arrived for an Apple-bound identity with no identity token on
    /// it. The client is expected to ask Apple for one first; a client that
    /// believes it never signed in reaches this too, and the answer is the same.
    #[error("deleting an account signed in with Apple requires a fresh Apple credential")]
    CredentialRequired,

    /// The identity token is genuinely Apple's and names a *different* Apple
    /// account than the one this identity is bound to.
    ///
    /// Separate from [`AccountError::Rejected`] because nothing is wrong with
    /// the credential: somebody proved an Apple account, just not this one. A
    /// client that reported "your Apple ID was rejected" here would send a
    /// person to re-authenticate as the wrong account, repeatedly.
    #[error("this Apple account is not the one this identity is signed in with")]
    WrongAccount,

    /// The caller's row vanished between the identity layer creating it and this
    /// write. Unreachable short of a manual delete, and surfaced rather than
    /// quietly treated as a first sign-in.
    #[error("no user row for the calling user")]
    Missing,

    /// The binding was written but the credential proving it was not, so there
    /// is nothing to hand the client.
    ///
    /// Surfaced rather than answered with a credential-less success: a client
    /// that stored the returned id and nothing else would be refused every
    /// subsequent request with no idea why. Signing in again recovers it — see
    /// `service::sign_in_with_apple`.
    #[error("{0}")]
    Session(#[from] SessionError),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
}

/// Logs server-side faults before converting them.
///
/// Same rule as the other features: the client receives an opaque `internal`
/// status, so a silent conversion would leave the failure unreproducible from
/// outside the process.
///
/// The split inside [`AccountError::Rejected`] is the one that matters to a
/// person. A token this server refuses is `UNAUTHENTICATED` — they did not prove
/// the account is theirs, which is a different thing from a malformed field, and
/// `EntitlementService`'s `INVALID_ARGUMENT` would be the wrong word for a
/// credential. Apple being unreachable is `UNAVAILABLE`, because telling somebody
/// their Apple ID was rejected when the truth is that we could not ask would have
/// them re-authenticating against an outage.
///
/// The two erasure refusals divide the same way. Nothing presented is
/// `UNAUTHENTICATED` — go and get a credential — while a credential that proved
/// the wrong Apple account is `PERMISSION_DENIED`, because the caller
/// authenticated perfectly and simply may not do this.
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
            AccountError::Session(e) => {
                tracing::error!(feature = "account", error = %e, "could not mint a session credential");
                Self::internal("internal error")
            }
            AccountError::Database(e) => {
                tracing::error!(feature = "account", error = %e, "database error");
                Self::internal("internal error")
            }
        }
    }
}
