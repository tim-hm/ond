//! Technique errors and their gRPC status mapping.

use tonic::Status;

/// Why the catalogue could not be served.
///
/// Neither variant is the caller's doing — this service takes no identity and
/// its requests carry nothing to get wrong — so both travel as `internal` and
/// the detail stays in the log.
#[derive(Debug, thiserror::Error)]
pub enum TechniqueError {
    /// A technique with no stages, a stage with no phases, or a catalogue with
    /// no techniques at all. The foreign keys and the seed's own invariants
    /// make the first two unreachable, so reaching either means the schema
    /// changed under the read path — surfaced as `internal`, not silently
    /// dropped.
    ///
    /// The third is reachable, and is stretching the word: a database whose
    /// seed transaction has not committed is unseeded rather than inconsistent.
    /// It travels as this variant because the answer is the same — an opaque
    /// `internal` and a logged reason — and a variant of its own would be one
    /// no caller could act on differently. [`super::cache`] carries why it must
    /// not be cached.
    #[error("{0}")]
    Inconsistent(String),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
}

/// Logs server-side faults before converting them.
///
/// The client only ever receives an opaque `internal` status, so a conversion
/// that stays silent leaves the failure unreproducible from outside the process.
/// The sqlx error is deliberately not forwarded — it can carry table and column
/// names, and the log is where that detail belongs.
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
