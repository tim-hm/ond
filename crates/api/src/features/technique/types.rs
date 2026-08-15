//! Domain enums, mirroring the Postgres types declared in `0001_init.sql`, and
//! the one shape another feature reads.
//!
//! The enums are distinct from the generated proto enums on purpose. A proto
//! enum is an `i32` with an `_UNSPECIFIED` zero value that the wire format can
//! always produce; these types have no such variant, so a value that reaches the
//! repository is already known to be one of the four the database accepts.

/// Mirrors the `technique_goal` Postgres enum.
///
/// `Deserialize` is the assistant's tool arguments arriving as JSON: a model
/// that invents a goal fails the parse rather than reaching a fallback arm, and
/// a goal added to the Postgres enum then has exactly one place to be mapped
/// from — see [`super::convert::goal_to_proto`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, serde::Deserialize)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "snake_case")]
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

/// Mirrors the `copy_register` Postgres enum — which words the session an
/// occasion prescribes speaks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "copy_register", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CopyRegister {
    Plain,
    Playful,
}

/// Mirrors the `passage` Postgres enum.
///
/// `Deserialize` for [`TechniqueGoal`]'s reason: it is the vocabulary the
/// assistant's tool schema declares, and one mapping to the wire is better than
/// two that can disagree.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, serde::Deserialize)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "snake_case")]
pub enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

/// Mirrors the `manner` Postgres enum.
///
/// No `Deserialize`, unlike [`Passage`] and [`TechniqueGoal`]: that derive is
/// there because the assistant's tool schema declares those vocabularies, and it
/// does not declare this one. An author does not assert physiology, so nothing
/// inbound ever names a manner.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "manner", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Manner {
    CurledTongue,
    PursedLips,
    Hum,
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

    /// The curated sentence: what it does and when to reach for it. What the
    /// assistant is briefed with, so the model describes an exercise in the same
    /// words the person reading its screen just saw.
    ///
    pub summary: String,

    /// Why the exercise works, in the paragraph the person reads on its own
    /// screen.
    ///
    /// The prefix orders the coach to name the mechanism — vagal tone, CO2
    /// tolerance, a slow rate letting heart rhythm and breath fall into step.
    /// Without this it obeyed that from the model's own knowledge, free to
    /// drift from the curated paragraph the person had just read; with it the
    /// two say the same thing. Distinct from `evidence`, which stays behind on
    /// purpose — see [`super::service::catalogue`].
    pub mechanism: String,

    pub goal: TechniqueGoal,

    /// The curated caution, empty for the techniques that carry none.
    ///
    /// The assistant is told never to contradict one, which it cannot honour
    /// without being shown them, and only two techniques have a note: both say
    /// where the person must be sitting and when to stop. The children's rule
    /// is not among them — it belongs to the `with-your-child` occasion, which
    /// is what keeps it on the route that can reach a child rather than on an
    /// exercise an adult may pick for themselves.
    pub safety_note: String,

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

    /// How the breath is shaped, `None` for all but three phases in the seeded
    /// catalogue. Carried for the wire projection on `passage`'s terms; the
    /// assistant never reads it.
    pub manner: Option<Manner>,

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
            mechanism: "a mechanism".to_owned(),
            goal,
            safety_note: String::new(),
            recommended_rounds: 1,
            stages: vec![PlayableStage {
                cycles: 4,
                open_ended: false,
                phases: vec![
                    PlayablePhase {
                        kind: PhaseKind::Inhale,
                        passage: Some(Passage::Nose),
                        manner: None,
                        duration_ms: 4000,
                        min_duration_ms: 2000,
                        max_duration_ms: 8000,
                    },
                    PlayablePhase {
                        kind: PhaseKind::Exhale,
                        passage: Some(Passage::Nose),
                        manner: None,
                        duration_ms: 4000,
                        min_duration_ms: 2000,
                        max_duration_ms: 8000,
                    },
                ],
            }],
        }
    }
}

/// The curated reference data, as another feature reads it.
///
/// Everything here is seeded, identical for every caller, and changes only when
/// the content does — which is exactly what makes it worth putting in the
/// assistant's cached prefix. Returned as one value because it is read as one:
/// the coach that can name a moment should be able to name the progression too.
pub struct Reference {
    pub occasions: Vec<Occasion>,
    pub progression: Vec<ProgressionStep>,
    pub foundations: Vec<FoundationHeading>,
}

/// One curated entry point into the catalogue, as a mapping rather than as
/// copy.
///
/// The seeded `name` and `summary` are deliberately absent. They are marked
/// provisional pending TIM-28, and quoting provisional copy into the coach's
/// mouth would put two voices out of step on the same screen. What the coach
/// needs is the prescription: which exercise, how long, how loudly, and any
/// rhythm or caution belonging to the protocol rather than the exercise.
/// The seeded `goal` is absent too, and for a different reason: an occasion may
/// borrow a goal its technique does not have, which is a curation decision the
/// screens act on and the coach has no use for — it names the exercise, not the
/// category.
pub struct Occasion {
    pub slug: String,
    pub technique_slug: String,
    pub surface: DeliverySurface,
    pub duration_ms: i32,
    pub phase_durations_ms: Vec<i32>,
    pub safety_note: String,
}

/// One rung of the Start here progression, in curated order. The seeded `note`
/// is left behind for [`Occasion`]'s reason.
pub struct ProgressionStep {
    pub technique_slug: String,
}

/// One foundation topic's slug and question, without its answer.
///
/// The index, not the content. Thirteen questions cost about a hundred tokens
/// and tell the model the app holds a considered position on nose-versus-mouth
/// and hold length, so it can stay in that lane; the thirteen answers would cost
/// fourteen hundred to supply phrasings a model of this class already matches.
pub struct FoundationHeading {
    pub slug: String,
    pub question: String,
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
/// the prompt's echo guard, and the fallback's goal attribution. That decision
/// is load-bearing for safety (an unresolvable slug
/// is client free text and must never reach a client or a prompt), so any
/// change to how a slug matches happens here or nowhere.
pub fn resolve<'a>(catalogue: &'a [Technique], slug: &str) -> Option<&'a Technique> {
    catalogue.iter().find(|technique| technique.slug == slug)
}
