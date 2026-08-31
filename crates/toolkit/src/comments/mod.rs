//! Comment extraction for the prose-length check.
//!
//! The scanner skips quoted strings and returns adjacent full-line comments
//! as one block, across the hand-written formats in this repository.

mod files;
pub mod length;
mod lex;
mod scan;

pub use files::{files, relative};
pub use scan::{CommentBlock, blocks};
