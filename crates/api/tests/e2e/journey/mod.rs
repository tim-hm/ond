//! `JourneyService` over the wire the iOS client uses. Split the ways the
//! feature is: the history a person records, the two measurements they take,
//! the boards that rank everyone — and the practice snapshot derived from
//! them. What they all build sessions and identities out of is [`fixtures`].

mod bolt;
mod fixtures;
mod leaderboard;
mod resting_rate;
mod sessions;
mod snapshot;
