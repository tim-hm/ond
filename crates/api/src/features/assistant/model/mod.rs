//! The seam every language model sits behind. One trait, three
//! implementations: [`bedrock`] calls a provider,
//! [`disabled::DisabledModelClient`] calls nothing, and the integration tests
//! script one. Everything else is written against the trait, so the only
//! untested code is the thin layer that builds a request body.

pub mod bedrock;
pub mod breaker;
pub mod disabled;
mod install;
mod types;

pub use self::install::install;
pub use self::types::{
    AssistantMode, ChatRole, ChatTurn, ModelChunk, ModelClient, ModelError, ModelRequest,
    ModelStream, ToolSpec,
};
