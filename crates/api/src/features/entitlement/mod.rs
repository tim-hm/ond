//! Entitlement — one auto-renewable subscription, verified once and stored
//! against the anonymous identity. `StoreKit` answers all UI gating on the
//! device, offline; what lands here is the same purchase re-asserted so the
//! server can check the two decisions that must not be the client's: spending
//! a model call, and reading a leaderboard. Readers use [`service::tier`] only.

pub mod cache;
pub mod errors;
pub mod handlers;
pub mod metrics;
pub mod repository;
pub mod service;
pub mod types;
pub mod verifier;
