//! Seeds the technique catalogue, the breathing foundations, and the routes into
//! it: the occasion entries and the Start here progression. The values live in
//! `seed/catalogue.rs`; this module validates, exports, and reconciles them. Its
//! queries are runtime `sqlx::query`, not the checked macros, because this crate
//! runs before the schema exists.

mod catalogue;
mod export;
#[cfg(test)]
mod invariants;
mod repository;
mod types;

pub use export::catalogue_json;
pub use repository::run;
use types::{
    CopyRegister, DeliverySurface, EvidenceGrade, FoundationSeed, HapticPattern, Manner,
    OccasionSeed, Passage, ProgressionStepSeed, ReadingContentSeed, TechniqueGoal, TechniqueSeed,
    exhale, hold_in, hold_out, inhale, open_ended_stage, shaped_exhale, shaped_inhale, stage,
};
