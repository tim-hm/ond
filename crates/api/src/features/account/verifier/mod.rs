//! The seam every Sign in with Apple credential arrives through: one trait,
//! [`apple`] checking real signatures against Apple's published keys, and a
//! scripted test implementation, so the binding and merge are testable with no
//! network. Async, unlike `TransactionVerifier`: a transaction carries its own
//! certificate chain, but an identity token's key is fetched from Apple.

pub mod apple;
mod types;

pub use self::apple::AppleIdentityVerifier;
pub use self::types::{IdentityTokenVerifier, VerificationError, VerifiedIdentity};
