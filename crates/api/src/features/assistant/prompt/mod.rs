//! What the model is told, and what is believed of what it says back. Split
//! at the cache boundary: [`catalogue_prefix`] is identical for every caller
//! and changes only when the seed does, so the provider caches it; everything
//! per-person is built by the `*_instruction` functions and goes after it.
//! Believing the reply is `super::parse`'s business, not this module's.

mod instructions;
mod prefix;

pub use self::instructions::{chat_instruction, recommendation_instruction};
pub use self::prefix::{catalogue_prefix, offered_line};
