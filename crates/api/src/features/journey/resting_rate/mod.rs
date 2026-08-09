//! Resting rate — how many breaths a minute somebody takes when they are not
//! doing anything about it.
//!
//! The second measurement the app takes, and deliberately not a second reading
//! of the first. A pause measures CO2 tolerance; this measures the habitual
//! pattern underneath it, so the two can move independently and a coach reading
//! both learns something it could not learn from either.
//!
//! Its own sub-feature beside `bolt` rather than folded in with it: the two are
//! measured differently, bounded differently, and read in opposite directions —
//! a long pause is good and a slow rate is good, which is the same word for
//! opposite arithmetic. The duplication between the two is the one this
//! codebase's rule allows; a third measurement is what should collapse them
//! into a single kinded table rather than a third copy of this shape.

pub mod repository;
pub mod service;
pub mod types;
