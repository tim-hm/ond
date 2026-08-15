//! Assistant errors and their gRPC status mapping.
//!
//! Conspicuously short, because the model failing is not one of them: an
//! unreachable model, a tripped breaker, and an exhausted quota all produce a
//! successful response flagged `FALLBACK`. What remains here is malformed chat
//! input or one of the reads needed to derive the fallback failing.

use tonic::Status;

use crate::features::entitlement::errors::EntitlementError;
use crate::features::journey::errors::JourneyError;
use crate::features::profile::errors::ProfileError;
use crate::features::technique::errors::TechniqueError;
use crate::features::user_technique::errors::UserTechniqueError;

/// Why the assistant could not answer at all.
///
/// Short by design: the model failing is not one of these. An unreachable
/// provider, a tripped breaker and an exhausted quota all produce a successful
/// response flagged `FALLBACK`, so what is left is malformed input or a read
/// the fallback itself needs.
#[derive(Debug, thiserror::Error)]
pub enum AssistantError {
    /// The chat request itself was malformed — an empty or over-long message,
    /// an over-long history turn, or a turn that does not say who spoke.
    /// Reported verbatim: only a client bug produces one, and the message is
    /// what names the bug.
    #[error("{0}")]
    InvalidChat(String),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    /// Reading the caller's profile failed. Folded in rather than re-modelled:
    /// the profile feature owns what can go wrong with a profile, and repeating
    /// its variants here would be two places to keep in step.
    #[error("profile error: {0}")]
    Profile(#[from] ProfileError),

    /// Reading the catalogue failed, likewise — including the case where it
    /// came back empty, which `technique::cache` refuses rather than caches so
    /// that there is nothing to recommend *and* nothing poisoned for the rest
    /// of the process.
    #[error("technique error: {0}")]
    Technique(#[from] TechniqueError),

    /// Reading the caller's practice snapshot failed, likewise.
    #[error("journey error: {0}")]
    Journey(#[from] JourneyError),

    /// Reading what the caller is entitled to failed. Fatal rather than read as
    /// "free", because it is the same row and the same connection the profile
    /// read above needs — a database that cannot answer this one has already
    /// failed the call.
    #[error("entitlement error: {0}")]
    Entitlement(#[from] EntitlementError),

    /// Reading the exercises the caller has saved failed, likewise. Fatal on
    /// the same terms as the rest of the fan-out rather than degrading to an
    /// empty list: an empty list is a real answer meaning "they have made
    /// none", and a failed read that borrowed it would have the coach offer to
    /// save something they already have.
    #[error("user technique error: {0}")]
    UserTechnique(#[from] UserTechniqueError),
}

/// Logs server-side faults before converting them.
///
/// Same rule as the other features: the client receives an opaque `internal`
/// status, so a silent conversion would leave the failure unreproducible from
/// outside the process.
impl From<AssistantError> for Status {
    fn from(error: AssistantError) -> Self {
        match error {
            AssistantError::InvalidChat(message) => Self::invalid_argument(message),
            AssistantError::Database(e) => {
                tracing::error!(feature = "assistant", error = %e, "database error");
                Self::internal("internal error")
            }
            AssistantError::Profile(e) => e.into(),
            AssistantError::Technique(e) => e.into(),
            AssistantError::Journey(e) => e.into(),
            AssistantError::Entitlement(e) => e.into(),
            AssistantError::UserTechnique(e) => e.into(),
        }
    }
}
