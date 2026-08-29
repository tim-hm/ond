//! Technique errors and their gRPC status mapping.

use tonic::Status;

/// Why the catalogue could not be served.
///
/// Neither variant is the caller's doing — this service takes no identity and
/// its requests carry nothing to get wrong — so both travel as `internal` and
/// the detail stays in the log.
#[derive(Debug, thiserror::Error)]
pub enum TechniqueError {
    /// A technique with no stages, a stage with no phases, or a catalogue with no techniques.
    ///
    /// Foreign keys and the seed make the first two unreachable, so either one means the schema
    /// changed under the read path. The third is an uncommitted seed rather than corruption, sharing
    /// this variant because no caller could act on the two differently. [`super::cache`] says why.
    #[error("{0}")]
    Inconsistent(String),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
}

/// Logs server-side faults before converting them.
///
/// The client only ever receives an opaque `internal`, so a silent conversion would leave the
/// failure unreproducible from outside the process. The sqlx error is deliberately not
/// forwarded: it can carry table and column names, which belong in the log.
impl From<TechniqueError> for Status {
    fn from(error: TechniqueError) -> Self {
        match error {
            TechniqueError::Inconsistent(message) => {
                tracing::error!(feature = "technique", error = %message, "inconsistent catalogue");
                Self::internal("internal error")
            }
            TechniqueError::Database(e) => {
                tracing::error!(feature = "technique", error = %e, "database error");
                Self::internal("internal error")
            }
        }
    }
}

/// Carries `crate::wire`'s narrowing failures as this feature's own
/// corrupt-data case, which is what lets a call site stay a bare `?`.
impl From<crate::wire::Unrepresentable> for TechniqueError {
    fn from(error: crate::wire::Unrepresentable) -> Self {
        Self::Inconsistent(error.0)
    }
}
