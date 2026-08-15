//! Journey — what a person has actually done, and where that puts them.
//!
//! Sessions, controlled-pause scores, and resting-rate readings are three
//! append-only histories. A client can therefore re-send a batch it is unsure
//! about, and a streak is folded for whichever time zone the person is standing
//! in today rather than kept as a counter to repair. Leaderboards are the one
//! derived value persisted: a refreshable snapshot and its bounded listing turn
//! population-wide folds into keyed reads, and expire independently from the
//! histories they summarize.
//!
//! Tier 3, on the boundary the code already had: `sessions` records and returns
//! history, `bolt` keeps the controlled-pause measurements, and `leaderboard`
//! `resting_rate` holds the manual reading, and `leaderboard` ranks people
//! against each other. They change for entirely different reasons. The edges
//! between them belong to `GetJourney`, which draws the whole journey screen:
//! `sessions::service` reads the BOLT and resting-rate snapshots through their
//! sibling *services*. A sub-feature never reaches into a sibling's repository,
//! which is the same rule that holds between features.

pub mod bolt;
pub mod errors;
pub mod handlers;
pub mod leaderboard;
pub mod resting_rate;
pub mod sessions;
pub mod wire;
