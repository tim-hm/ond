//! The seam every Sign in with Apple credential arrives through.
//!
//! One trait and two implementations, in the shape `entitlement::verifier`
//! established: [`apple`] checks a real signature against Apple's published
//! keys, and the integration tests script one. That split is what makes the rest
//! of the feature — the binding, the merge, the transaction it runs in —
//! testable with nothing Apple signed and no network.
//!
//! Unlike `TransactionVerifier`, this one is **async**, and the difference is
//! not stylistic. An App Store transaction carries its own certificate chain, so
//! verifying it is arithmetic over bytes the caller already holds. An identity
//! token carries only a key id, and the key itself is fetched from Apple — so
//! there really is a round trip to await, however rarely it happens.

pub mod apple;
pub mod types;

pub use self::apple::AppleIdentityVerifier;
pub use self::types::{IdentityTokenVerifier, VerificationError, VerifiedIdentity};
