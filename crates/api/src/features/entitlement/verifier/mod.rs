//! The seam every App Store transaction arrives through.
//!
//! One trait and two implementations: [`appstore`] checks a real signature, and
//! the integration tests script one. That split is what makes the whole feature
//! — the storage, the idempotency, the revocation path, the tier the assistant
//! reads — testable with no Apple-signed material and no network.
//!
//! `appstore` reads the App Store's transaction format; `chain` decides whether
//! a certificate chain is Apple's and knows nothing else. `chain` is private
//! because the split is an implementation detail of verifying a transaction —
//! nothing outside this module has a chain to check.
//!
//! Deliberately synchronous. Verification is a signature check over bytes the
//! caller already holds; there is nothing to await, and an `async fn` here would
//! promise a round-trip the design specifically avoids.

pub mod appstore;
mod chain;
mod types;

pub use self::appstore::AppStoreVerifier;
pub use self::types::{TransactionVerifier, VerificationError, VerifiedTransaction};
