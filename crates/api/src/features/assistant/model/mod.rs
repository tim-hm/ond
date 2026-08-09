//! The seam every language model sits behind.
//!
//! One trait, three implementations: [`bedrock`] calls a provider,
//! [`disabled::DisabledModelClient`] calls nothing, and the integration tests
//! script one. Everything else in this feature — quota, circuit breaker,
//! validation, fallback — is written against the trait, so all of it is
//! exercised without a network call and the only untested code is the thin layer
//! that builds a request body.
//!
//! [`types`] defines the seam and [`install`] chooses which side of it this
//! process gets; the three implementations sit beside them.

pub mod bedrock;
pub mod breaker;
pub mod disabled;
mod install;
mod types;

pub use self::install::install;
pub use self::types::{
    AssistantMode, ChatRole, ChatTurn, ModelClient, ModelError, ModelRequest, ModelStream,
};
