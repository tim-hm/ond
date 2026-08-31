//! What the model is told, and what is believed of what it says back. Split
//! at the cache boundary: [`PrefixCache`] holds the half every caller shares,
//! which changes only when the seed does, so the provider caches it;
//! everything per-person is built by the `*_instruction` functions after it.
//! Believing the reply is `super::parse`'s business, not this module's.

mod instructions;
mod prefix;

pub use self::instructions::{chat_instruction, recommendation_instruction};
pub use self::prefix::{PrefixCache, offered_line};
