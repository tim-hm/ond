//! Resting rate — breaths a minute when somebody is not doing anything about it.
//!
//! A pause measures CO2 tolerance; this measures the habitual pattern
//! underneath, so the two move independently. Its own sub-feature beside `bolt`
//! because the two are bounded differently and read in opposite directions.

pub mod repository;
pub mod service;
pub mod types;
