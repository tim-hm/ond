//! The seam every App Store transaction arrives through. One trait and two
//! implementations: [`appstore`] checks a real signature, and the integration
//! tests script one, so the whole feature is testable with no Apple-signed
//! material and no network. `chain` is private. Deliberately synchronous: this
//! is a signature check over bytes the caller already holds.
pub mod appstore;
mod chain;
mod types;

pub use self::appstore::AppStoreVerifier;
pub use self::types::{
    StoreEnvironment, TransactionVerifier, VerificationError, VerifiedTransaction,
};
