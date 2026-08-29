//! The exercises a person composed for themselves, stored against the identity
//! `crate::identity` resolves, so the phone and the watch see one list.
//!
//! Separate from `technique`, which serves curated reference data to anybody.
//! Here the seeded safe ranges are enforced — see [`repository::phase_limits`].

pub mod cache;
mod convert;
pub mod errors;
pub mod handlers;
pub mod repository;
pub mod service;
pub mod types;
mod validation;
