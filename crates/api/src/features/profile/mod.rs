//! Profile — the answers onboarding collects, stored against the anonymous
//! identity that `crate::identity` resolves.
//!
//! `crate::identity` creates the `users` row on the first RPC of any kind. This
//! feature owns only what a person has told the app about themselves.

pub mod errors;
pub mod handlers;
pub mod repository;
pub mod service;
pub mod types;
