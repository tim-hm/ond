//! Technique — the breathing techniques, the stages they play, the foundations served
//! alongside them, and the curated routes into them.
//!
//! The contract puts all four on `TechniqueService`: one body of reference data, read by the same
//! client on the same terms. A route resolves to a technique slug and adds nothing of its own.

pub mod cache;
pub(crate) mod convert;
pub mod errors;
pub mod handlers;
pub mod repository;
pub mod service;
pub mod types;
