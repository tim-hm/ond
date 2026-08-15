//! Technique — the catalogue of breathing techniques, the stages they play, the
//! breathing foundations served alongside them, and the curated routes into
//! them.
//!
//! The foundations live here rather than in a feature of their own because the
//! contract puts them on `TechniqueService`: they are the other half of the
//! catalogue's reference data, read by the same client on the same terms. The
//! occasion entries and the Start here progression are here for the same
//! reason and one more — a route resolves to a technique slug and adds nothing
//! to the catalogue, so it has no meaning apart from the list it points into.

pub mod cache;
pub(crate) mod convert;
pub mod errors;
pub mod handlers;
pub mod repository;
pub mod service;
pub mod types;
