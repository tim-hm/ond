//! Domain enums, mirroring the Postgres types declared in `0001_init.sql`, and
//! the one shape another feature reads.
//!
//! The enums are distinct from the generated proto enums on purpose. A proto
//! enum is an `i32` with an `_UNSPECIFIED` zero value that the wire format can
//! always produce; these types have no such variant, so a value that reaches the
//! repository is already known to be one of the four the database accepts.

/// Mirrors the `technique_goal` Postgres enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TechniqueGoal {
    Calm,
    Sleep,
    Energy,
    Reset,
    Focus,
}

/// Mirrors the `phase_kind` Postgres enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "phase_kind", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PhaseKind {
    Inhale,
    HoldIn,
    Exhale,
    HoldOut,
}

impl PhaseKind {
    /// Whether the breath is moving rather than being held — which is exactly
    /// when a phase has a passage, on the wire and in the column's `CHECK`.
    pub const fn is_breathing(self) -> bool {
        matches!(self, Self::Inhale | Self::Exhale)
    }
}

/// Mirrors the `delivery_surface` Postgres enum — how loudly the session an
/// occasion prescribes runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "delivery_surface", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DeliverySurface {
    FullScreen,
    Discreet,
}

/// Mirrors the `passage` Postgres enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

/// One technique as another feature reads it.
///
/// The catalogue's description of a technique plus the stages that make it
/// playable: `assistant` names techniques, explains why they work, and clamps
/// the exercise offers a model proposes against each phase's own safe range —
/// which is why the stages ride along where they once did not. Returned by
/// [`super::service::catalogue`] so `TechniqueRow` — and the sort order,
/// subscription flag and surrogate id on it — stays inside this feature.
pub struct Technique {
    /// The stable name a client navigates by, and the only string the assistant
    /// is ever allowed to emit as a technique.
    pub slug: String,

    pub name: String,

    /// The curated sentence carrying the mechanism, which is what the
    /// rule-based explanation is built from.
    pub summary: String,

    /// The caution it carries, empty where it carries none.
    pub safety_note: String,

    pub goal: TechniqueGoal,

    /// How many rounds the catalogue suggests, always positive.
    pub recommended_rounds: i32,

    /// The playable shape, in play order and never empty — the assembly refuses
    /// a stageless technique on the same corrupt-data terms as the proto path.
    pub stages: Vec<PlayableStage>,
}

/// One stage of a technique as another feature reads it.
pub struct PlayableStage {
    /// How many times the phases repeat, always positive.
    pub cycles: i32,

    /// An open-ended stage runs until the person ends it; its `cycles` value is
    /// presentational and an offer never overrides it.
    pub open_ended: bool,

    /// In cycle order, never empty.
    pub phases: Vec<PlayablePhase>,
}

/// One phase of a stage, carrying its curated duration and the safe range the
/// dial — and any exercise offer — must stay inside.
pub struct PlayablePhase {
    pub kind: PhaseKind,

    /// Where the air goes, `None` for a hold. Carried for the wire projection
    /// in `service::stage_to_proto`; the assistant reads the shape and the
    /// ranges, never this.
    pub passage: Option<Passage>,

    pub duration_ms: i32,
    pub min_duration_ms: i32,
    pub max_duration_ms: i32,
}

#[cfg(test)]
impl Technique {
    /// A representative fixture: one stage of four cycles, breathing 4s in and
    /// 4s out inside a 2s–8s range, one recommended round. Shared by every
    /// assistant test that needs a catalogue, so the playable shape lives in
    /// one place instead of one copy per test module.
    pub fn test(slug: &str, goal: TechniqueGoal) -> Self {
        Self {
            slug: slug.to_owned(),
            name: slug.to_owned(),
            summary: "a summary".to_owned(),
            safety_note: String::new(),
            goal,
            recommended_rounds: 1,
            stages: vec![PlayableStage {
                cycles: 4,
                open_ended: false,
                phases: vec![
                    PlayablePhase {
                        kind: PhaseKind::Inhale,
                        passage: Some(Passage::Nose),
                        duration_ms: 4000,
                        min_duration_ms: 2000,
                        max_duration_ms: 8000,
                    },
                    PlayablePhase {
                        kind: PhaseKind::Exhale,
                        passage: Some(Passage::Nose),
                        duration_ms: 4000,
                        min_duration_ms: 2000,
                        max_duration_ms: 8000,
                    },
                ],
            }],
        }
    }
}

/// The longest slug the wire accepts, in characters — matching the `CHECK` on
/// `sessions.technique_slug`, and the bound every feature that reads a
/// client-supplied slug shares. Beside [`resolve`] because the two questions —
/// "could this be a slug" and "is it one" — must not drift apart per feature.
pub const MAX_SLUG_CHARS: usize = 64;

/// The technique a slug names, or `None` for one the catalogue does not hold.
///
/// The one definition of "resolves in the catalogue", shared by everything in
/// `assistant` that has to decide whether a slug is real — the reply parser,
/// the explanation lookup, the prompt's echo guard, and the fallback's goal
/// attribution. That decision is load-bearing for safety (an unresolvable slug
/// is client free text and must never reach a client or a prompt), so any
/// change to how a slug matches happens here or nowhere.
pub fn resolve<'a>(catalogue: &'a [Technique], slug: &str) -> Option<&'a Technique> {
    catalogue.iter().find(|technique| technique.slug == slug)
}
