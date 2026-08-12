//! What a person authored, and the limits it has to fit inside.
//!
//! Two kinds of limit live here, and only one of them is a constant. The safe
//! duration of a phase is the catalogue's answer and is read from it
//! ([`PhaseLimits`]); how many stages, cycles and rounds a technique may have is
//! structural — a ceiling on size rather than on physiology — and is stated
//! below.

use crate::features::technique::types::{Passage, PhaseKind, TechniqueGoal};

/// Matches the `CHECK` on `user_techniques.name`. Duplicated from the schema so
/// an over-long name comes back as `INVALID_ARGUMENT` naming the field, rather
/// than as the opaque `internal` a constraint violation would become.
pub const MAX_NAME_CHARS: u32 = 60;

/// Matches the `CHECK` on `user_techniques.summary`, and duplicated from the
/// schema for the same reason [`MAX_NAME_CHARS`] is.
///
/// The bound argued in 0015: the same 500 `users.intent_note` carries, which is
/// the difference between a sentence and a book, and comfortably above the 328
/// characters of the longest curated summary — a ceiling under that would let
/// the catalogue say something an author cannot.
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

/// Shorter than this, one breath in and out is over-breathing rather than
/// breathing slowly: four seconds is fifteen breaths a minute, the top of the
/// usual resting range.
///
/// The one physiological limit stated here rather than read from the catalogue,
/// and it has to be. [`PhaseLimits`] is a per-kind aggregate — the widest range
/// any closed stage seeds for an inhale, for a hold — so the coupling between a
/// pattern and the holds its own technique puts after it is exactly what that
/// aggregation throws away. A person composing from those ranges can breathe
/// twice a second and then hold, which no seeded technique does.
pub const FAST_BREATHING_CYCLE_MS: i32 = 4_000;

/// The longest a hold may be timed for in a technique that breathes fast
/// anywhere in it — the blackout rule, on the authoring side.
///
/// Hyperventilation followed by a measured breath-hold is the documented way to
/// faint doing this. The seeded catalogue is held to the same number by
/// `no_hold_after_fast_breathing_is_a_target` in `crates/migrate`, restated
/// here because `api` does not depend on `migrate` — the same duplication
/// [`MAX_NAME_CHARS`] pays against the schema, and for the same reason: the
/// alternative is a refusal nobody can read.
///
/// An authored technique has no open-ended escape, deliberately — 0012 leaves
/// the column off `user_technique_stages` entirely — so this ceiling is the
/// whole of the rule on this side rather than half of it.
///
/// Today it refuses nothing: the widest hold the catalogue derives is the Wim
/// Hof recovery dial's own top, which is this number, so no draft can currently
/// exceed it. That is a coincidence of two figures with no link between them,
/// not a reason to drop the rule — seed one slow technique with a longer closed
/// hold and the derived ceiling rises on its own, silently, taking the authored
/// path with it. This is what stops that being a safety change nobody noticed
/// making.
pub const TIMED_HOLD_CEILING_MS: i32 = 20_000;

/// How many techniques one person may keep.
///
/// Not a product ceiling anybody asked for — it is the bound on what a caller
/// whose whole credential is a UUID they generated can make this database
/// store. Generous enough that reaching it means somebody is collecting rather
/// than practising.
pub const MAX_TECHNIQUES: u32 = 20;

/// A technique as somebody composed it, after validation.
///
/// Distinct from the proto draft in exactly the way `technique::types`' enums
/// are distinct from the generated ones: every value in here has already been
/// checked against the limits, so the repository writes without a second
/// opinion and the `CHECK`s below it are a backstop rather than the guard.
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

pub struct AuthoredStage {
    /// In cycle order. Never empty.
    pub phases: Vec<AuthoredPhase>,
    pub cycles: i32,
}

/// One phase as somebody composed it, with the two things they did not state
/// already resolved.
///
/// `kind` is derived rather than sent: the draft says inhale, hold or exhale,
/// and which of the two holds a hold is follows from the breath before it. And
/// `passage` is `None` exactly when `kind` is a hold, which the draft's oneof
/// makes unrepresentable rather than merely refused — the hold arm has no
/// passage to read.
pub struct AuthoredPhase {
    pub kind: PhaseKind,
    pub passage: Option<Passage>,
    pub duration_ms: i32,
}

/// The safe duration range for each phase kind somebody may author.
///
/// Derived from the seeded catalogue rather than declared — see
/// [`super::repository::phase_limits`] for the query and why open-ended stages
/// are left out of it. Held as a list rather than a map because there are four
/// kinds and the wire wants it ordered anyway.
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

    /// The range a phase of `kind` may be authored within, or `None` for a kind
    /// the catalogue never uses in a closed stage.
    ///
    /// `None` is a refusal rather than a fallback: a kind with no seeded range
    /// has no evidence behind any duration, and inventing one here would be this
    /// server making up the safety limit it exists to enforce.
    pub fn range(&self, kind: PhaseKind) -> Option<&PhaseLimit> {
        self.0.iter().find(|limit| limit.kind == kind)
    }

    /// The limits in the order they were derived — the enum's declaration
    /// order, which is the order a cycle runs in and a picker renders.
    pub fn iter(&self) -> impl Iterator<Item = &PhaseLimit> {
        self.0.iter()
    }
}
