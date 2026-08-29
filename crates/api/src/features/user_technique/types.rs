//! What a person authored, and the limits it has to fit inside.
//!
//! A phase's safe duration is the catalogue's answer, read from it through
//! [`PhaseLimits`]. The counts of stages, cycles and rounds are structural
//! ceilings on size rather than on physiology, and are stated below.

use crate::features::technique::types::{Passage, PhaseKind, TechniqueGoal};

/// Matches the `CHECK` on `user_techniques.name`. Duplicated from the schema so
/// an over-long name comes back as `INVALID_ARGUMENT` naming the field, rather
/// than as the opaque `internal` a constraint violation would become.
pub const MAX_NAME_CHARS: u32 = 60;

/// Matches the `CHECK` on `user_techniques.summary`, and duplicated from the
/// schema for the same reason [`MAX_NAME_CHARS`] is. 0015 argues the bound:
/// the same 500 `users.intent_note` carries, and above the 328 characters of
/// the longest curated summary. A lower ceiling would let the catalogue say
/// something an author cannot.
pub const MAX_SUMMARY_CHARS: u32 = 500;

/// As many stages as the longest seeded protocol has — the four of a Wim
/// Hof-style round. A ceiling on complexity rather than on safety: nothing
/// composed of closed stages gets dangerous by having another one, but an
/// unbounded stage list is an unbounded write.
pub const MAX_STAGES: u32 = 4;

/// Twice the longest seeded pattern (box breathing's four beats), so a person
/// can compose something the catalogue does not contain without the list
/// becoming a place to store a session's worth of individually timed breaths.
pub const MAX_PHASES_PER_STAGE: u32 = 8;

/// The same ceilings the iOS dials already offer on a catalogue technique
/// (`TechniqueOverrides.cycleRange` and `.roundRange`). Restated here because
/// this is the side that decides, and a client is free to offer less.
pub const MAX_CYCLES: i32 = 99;
pub const MAX_ROUNDS: i32 = 10;

/// How many techniques one person may keep.
///
/// Not a product ceiling. It bounds what a caller whose whole credential is a
/// UUID they generated can make this database store. Reaching it means
/// somebody is collecting rather than practising.
pub const MAX_TECHNIQUES: u32 = 20;

/// A technique as somebody composed it, after validation.
///
/// Every value here is already checked against the limits, so the repository
/// writes without a second opinion. The column `CHECK`s are a backstop rather
/// than the guard.
pub struct AuthoredTechnique {
    pub name: String,
    /// What they reach for it for. Empty where they said nothing, which is
    /// ordinary — and the same empty string a curated technique with no summary
    /// would carry.
    pub summary: String,
    pub goal: TechniqueGoal,
    pub rounds: i32,
    /// In play order. Never empty.
    pub stages: Vec<AuthoredStage>,
}

/// One of somebody's own exercises, as the coach is briefed on it.
///
/// The name and the goal only — see [`super::service::saved_summaries`] for
/// why this is not the playable shape. The name is what they typed, so it
/// reaches the prompt as data, not as anything the model should act on.
pub struct SavedSummary {
    pub name: String,
    pub goal: TechniqueGoal,
}

pub struct AuthoredStage {
    /// In cycle order. Never empty.
    pub phases: Vec<AuthoredPhase>,
    pub cycles: i32,
}

/// One phase as somebody composed it, with the two derived values resolved.
///
/// `kind` follows from the breath before a hold. `passage` is `None` exactly
/// when `kind` is a hold, which the draft's oneof makes unrepresentable rather
/// than merely refused.
pub struct AuthoredPhase {
    pub kind: PhaseKind,
    pub passage: Option<Passage>,
    pub duration_ms: i32,
}

/// The safe duration range for each phase kind somebody may author. Derived
/// from the seeded catalogue — see [`super::repository::phase_limits`] for the
/// query and why open-ended stages are left out, and
/// [`super::cache::PhaseLimitsCache`] for why it is derived once per process.
/// A list, not a map: there are four kinds, and the wire wants them ordered.
pub struct PhaseLimits(Vec<PhaseLimit>);

pub struct PhaseLimit {
    pub kind: PhaseKind,
    pub min_duration_ms: i32,
    pub max_duration_ms: i32,
}

impl PhaseLimits {
    /// Wraps limits already derived — by `repository::phase_limits`, or by a
    /// test that states its own.
    pub const fn new(limits: Vec<PhaseLimit>) -> Self {
        Self(limits)
    }

    /// The range a phase of `kind` may be authored within, or `None` for a
    /// kind the catalogue never uses in a closed stage. `None` refuses rather
    /// than falls back: a kind with no seeded range has no evidence behind any
    /// duration, and inventing one would be this server making up the safety
    /// limit it exists to enforce.
    pub fn range(&self, kind: PhaseKind) -> Option<&PhaseLimit> {
        self.0.iter().find(|limit| limit.kind == kind)
    }

    /// The limits in the order they were derived — the enum's declaration
    /// order, which is the order a cycle runs in and a picker renders.
    pub fn iter(&self) -> impl Iterator<Item = &PhaseLimit> {
        self.0.iter()
    }
}
