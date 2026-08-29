//! Journey — sessions, BOLT scores, resting-rate readings, and leaderboards.
//!
//! The three histories are append-only, so a resend is free and a streak is
//! folded per request for the caller's time zone. `GetJourney` owns the edges:
//! `sessions::service` reads sibling snapshots through services, not repositories.

pub mod bolt;
pub mod errors;
pub mod handlers;
pub mod leaderboard;
pub mod resting_rate;
pub mod sessions;
pub mod wire;
