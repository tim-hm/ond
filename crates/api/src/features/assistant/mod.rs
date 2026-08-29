//! Assistant — a language model reading the profile and the catalogue, and
//! the rules that answer when it cannot. `model/` is the provider seam, so
//! everything but `model/bedrock` tests offline. `prompt` and `parse` stay
//! separate: asking and believing the answer are different jobs, and only the
//! second is load-bearing for safety. Cross-feature reads go through services.

pub mod errors;
pub mod fallback;
pub mod handlers;
pub mod metrics;
pub mod model;
pub mod parse;
pub mod prompt;
pub mod repository;
pub mod service;
pub mod stream;
pub mod tools;
pub mod types;
