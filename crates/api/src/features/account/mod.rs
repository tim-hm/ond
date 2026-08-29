//! Account — Sign in with Apple, and the one place two identities become one.
//! Signing in is never required, which is why this is its own service and not
//! a gate in front of the others. The merge's full contract is documented on
//! `repository::merge`; `DeleteAccount` keeps nothing — the erasure that
//! `web/privacy.html` promises and Guideline 5.1.1(v) requires.

mod authorization;
pub mod errors;
pub mod handlers;
pub mod metrics;
pub mod repository;
pub mod service;
pub mod verifier;

pub use authorization::AuthorizationNonceHash;
