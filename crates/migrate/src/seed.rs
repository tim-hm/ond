//! Seeds the technique catalogue, the breathing foundations, and the routes into
//! it: the occasion entries and the Start here progression. The values live in
//! `seed/catalogue.rs`; this module validates, exports, and reconciles them. Its
//! queries are runtime `sqlx::query`, not the checked macros, because this crate
//! runs before the schema exists.

use anyhow::{Context, Result};
use serde::Serialize;
use sqlx::PgPool;

use self::catalogue::{FOUNDATIONS, OCCASIONS, PROGRESSION, TECHNIQUES};

mod catalogue;

/// Mirrors the `technique_goal` Postgres enum declared in `0001_init.sql`.
///
/// A local copy, because this crate creates the schema and must not depend on
/// `api`. It binds a value the database's own type system accepts, so a
/// mistyped label is a compile error rather than a failed migration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum TechniqueGoal {
    Calm,
    Sleep,
    Energy,
    Reset,
    Focus,
}

/// Mirrors the `phase_kind` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "phase_kind", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum PhaseKind {
    Inhale,
    HoldIn,
    Exhale,
    HoldOut,
}

/// `#[cfg(test)]` because seeding never asks the question — the constructors
/// below decide a phase's kind, and only the rules checking them care which
/// side of this line it fell. Without the gate it is dead code in the shipped
/// binary, which `check:rs` refuses.
#[cfg(test)]
impl PhaseKind {
    /// Whether air moves during this phase. Named rather than matched inline,
    /// because the negated form ("everything that is not either hold") is the
    /// one a reader has to invert in their head. The same predicate as
    /// `technique::types::PhaseKind::is_breathing`, restated because `migrate`
    /// does not depend on `api`.
    const fn is_breathing(self) -> bool {
        matches!(self, Self::Inhale | Self::Exhale)
    }
}

/// Mirrors the `passage` Postgres enum, on the same terms as [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

/// Mirrors the `manner` Postgres enum, on the same terms as [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "manner", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum Manner {
    CurledTongue,
    PursedLips,
    Hum,
}

impl Manner {
    /// The one breath each shape can be made on. A second copy of the
    /// `technique_phases_manner_fits_its_breath` constraint: the constraint
    /// catches a row however it arrives, and this catches the seed at compile
    /// time, because `TECHNIQUES` is a `const` and the `assert!` reading this
    /// runs during its evaluation.
    const fn shapes(self, kind: PhaseKind, passage: Passage) -> bool {
        matches!(
            (self, kind, passage),
            (Self::CurledTongue, PhaseKind::Inhale, Passage::Mouth)
                | (Self::PursedLips, PhaseKind::Exhale, Passage::Mouth)
                | (Self::Hum, PhaseKind::Exhale, Passage::Nose)
        )
    }
}

/// Mirrors the `delivery_surface` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "delivery_surface", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum DeliverySurface {
    FullScreen,
    Discreet,
}

/// Mirrors the `copy_register` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "copy_register", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum CopyRegister {
    Plain,
    Playful,
}

/// Mirrors the `evidence_grade` Postgres enum, on the same terms as
/// [`CopyRegister`].
///
/// The rubric each entry was graded against, and why there are two grades and
/// no `Strong`, are in `docs/product/breathing-science.md` §2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "evidence_grade", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum EvidenceGrade {
    Moderate,
    Limited,
}

/// How the items after a reading lead are presented.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum ReadingListStyle {
    None,
    Bullets,
    Numbered,
}

/// A short lead and, where the copy is genuinely list-shaped, its items.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
struct ReadingContentSeed {
    lead: &'static str,
    items: &'static [&'static str],
    list_style: ReadingListStyle,
}

impl ReadingContentSeed {
    /// A paragraph with no list.
    const fn prose(lead: &'static str) -> Self {
        Self {
            lead,
            items: &[],
            list_style: ReadingListStyle::None,
        }
    }

    /// A lead followed by unordered points.
    const fn bullets(lead: &'static str, items: &'static [&'static str]) -> Self {
        Self {
            lead,
            items,
            list_style: ReadingListStyle::Bullets,
        }
    }

    /// A lead followed by steps whose order matters.
    const fn numbered(lead: &'static str, items: &'static [&'static str]) -> Self {
        Self {
            lead,
            items,
            list_style: ReadingListStyle::Numbered,
        }
    }

    /// Whether the catalogue has nothing to say in this slot.
    const fn is_empty(self) -> bool {
        self.lead.is_empty() && self.items.is_empty()
    }

    /// The complete plain-text form sent to clients that predate the structure.
    fn plain_text(self) -> String {
        let mut text = self.lead.to_owned();

        if !self.items.is_empty() {
            if !text.is_empty() {
                text.push_str("\n\n");
            }

            for (index, item) in self.items.iter().enumerate() {
                if index > 0 {
                    text.push('\n');
                }
                match self.list_style {
                    ReadingListStyle::None => text.push_str(item),
                    ReadingListStyle::Bullets => {
                        text.push_str("• ");
                        text.push_str(item);
                    }
                    ReadingListStyle::Numbered => {
                        text.push_str(&(index + 1).to_string());
                        text.push_str(". ");
                        text.push_str(item);
                    }
                }
            }
        }

        text
    }
}

/// One phase: its kind, where the air goes, the curated default, and the range a
/// dial may move it within.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PhaseSeed {
    kind: PhaseKind,
    /// `None` exactly for a hold, matching the column's `CHECK`. Unreachable in
    /// any other combination because the four constructors below are the only
    /// way to build one of these.
    passage: Option<Passage>,
    /// How the breath is shaped, where the shape is what the technique turns on.
    /// `None` means "shaped no particular way", and most phases are. Unreachable
    /// on a breath it cannot shape: the two shaped constructors below check it
    /// against the column's own `CHECK` while `TECHNIQUES` is const-evaluated.
    manner: Option<Manner>,
    duration_ms: i32,
    min_duration_ms: i32,
    max_duration_ms: i32,
    /// The stillness closing this phase, the tap it plays and the line it
    /// speaks. Nothing authors any of them yet: a cadence is one deliverable
    /// per exercise, and that design does not exist.
    turn_gap_ms: Option<i32>,
    haptic_pattern: Option<&'static str>,
    voice_script: Option<&'static str>,
}

/// A run of cycles sharing one phase pattern.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StageSeed {
    phases: &'static [PhaseSeed],
    cycles: i32,
    /// Whether the person ends this stage rather than the clock.
    open_ended: bool,
}

/// One technique and the session it describes.
struct TechniqueSeed {
    slug: &'static str,
    name: &'static str,
    /// A row's worth: what it does and when to reach for it, short enough that
    /// they fit in a list.
    summary: &'static str,
    /// Why it works, as structured reading copy for the exercise's own screen.
    /// It sits beside `summary`, not as a longer version of it: one is a line in
    /// a list, the other is a page's opening argument. Lead with the likely
    /// benefit and use no more than three supporting points.
    /// `every_technique_opens_on_its_mechanism` requires one on every technique.
    mechanism: ReadingContentSeed,
    /// How strong the case for this exercise actually is, as a verdict and list.
    /// It never repeats `mechanism`: the mechanism cites a trial to say the
    /// exercise is not folklore, and this sizes the same trial.
    /// `every_technique_names_its_evidence` requires two or three points. Say
    /// what was shown, why it matters here, and what is still missing.
    evidence: ReadingContentSeed,
    /// The same judgement as `evidence`, in the one word a list row can carry.
    ///
    /// Seeded beside the evidence rather than inferred from it, so a rewritten
    /// sentence cannot quietly re-grade an exercise. Every curated technique
    /// carries one; `None` belongs to the exercises people write themselves.
    evidence_grade: EvidenceGrade,
    /// The caution this technique carries, empty where it carries none. The
    /// phone renders it as a full-screen warning between Begin and the countdown
    /// (`TechniqueWarningView`). The person silences it against this exact text,
    /// so rewording a note re-asks everyone who put it away. Blanking a note
    /// removes that warning; the watch and the assistant fallback show none.
    safety_note: &'static str,
    /// What to do with your body before the first breath, empty where the
    /// exercise asks for nothing. It is the part that does not change while the
    /// exercise runs, unlike the hint beside each breath. It is also where a
    /// shape offers an alternative: the cooling breath offers closed teeth to
    /// anybody whose tongue will not roll, which an enum case cannot say.
    preparation: ReadingContentSeed,
    goal: TechniqueGoal,
    stages: &'static [StageSeed],
    /// How many times a default session repeats the whole stage list. Curated
    /// per technique, and one for everything that is a single cycle repeated —
    /// rounds only earn their name in a staged protocol.
    recommended_rounds: i32,
    /// Whether this one is behind önd+. False for every technique at present:
    /// the whole catalogue is free while the featureset is still moving.
    /// Restoring the gate is typing `true` here. It is stated per technique with
    /// no default, so a new technique forces a decision.
    requires_subscription: bool,
}

/// A phase with the dial range it may be moved within, inclusive. A range of a
/// single point means the phase is not adjustable, which is the honest
/// description of a hold the person ends themselves. There are six constructors
/// rather than one taking a kind, so a hold has nowhere to put a passage and a
/// breath cannot omit one.
const fn inhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Inhale, passage, None, duration_ms, dial)
}

const fn exhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Exhale, passage, None, duration_ms, dial)
}

/// A breath the exercise shapes as well as places. A separate constructor rather
/// than a sixth argument, because three phases in the catalogue are shaped and
/// thirty-eight are not. The passage is still passed even though each manner
/// implies one, so `Passage::Mouth` stays legible at the cooling breath's call
/// site, and the `assert!` makes a disagreement a compile error.
const fn shaped_inhale(
    passage: Passage,
    manner: Manner,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    assert!(
        manner.shapes(PhaseKind::Inhale, passage),
        "a manner on an inhale it cannot shape"
    );
    breath(PhaseKind::Inhale, passage, Some(manner), duration_ms, dial)
}

const fn shaped_exhale(
    passage: Passage,
    manner: Manner,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    assert!(
        manner.shapes(PhaseKind::Exhale, passage),
        "a manner on an exhale it cannot shape"
    );
    breath(PhaseKind::Exhale, passage, Some(manner), duration_ms, dial)
}

const fn hold_in(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldIn, duration_ms, dial)
}

const fn hold_out(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldOut, duration_ms, dial)
}

const fn breath(
    kind: PhaseKind,
    passage: Passage,
    manner: Option<Manner>,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: Some(passage),
        manner,
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
        turn_gap_ms: None,
        haptic_pattern: None,
        voice_script: None,
    }
}

const fn hold(kind: PhaseKind, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: None,
        // Air that is not moving has no shape to hold, which the column's
        // `CHECK` states by naming a breathing kind in every arm.
        manner: None,
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
        turn_gap_ms: None,
        haptic_pattern: None,
        voice_script: None,
    }
}

const fn stage(phases: &'static [PhaseSeed], cycles: i32) -> StageSeed {
    StageSeed {
        phases,
        cycles,
        open_ended: false,
    }
}

/// A stage the clock does not end. One cycle by definition: repeating a hold
/// the person is already in charge of ending means nothing.
const fn open_ended_stage(phases: &'static [PhaseSeed]) -> StageSeed {
    StageSeed {
        phases,
        cycles: 1,
        open_ended: true,
    }
}

/// One question a beginner has, and the app's answer to it.
struct FoundationSeed {
    slug: &'static str,
    question: &'static str,
    answer: ReadingContentSeed,
}

/// A named moment and the prescription it resolves to.
///
/// Flat rather than holding a `PrescriptionSeed`: the four fields below the
/// copy *are* the prescription, and a nested struct would buy a name the wire
/// already carries at the cost of a second brace level per entry.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OccasionSeed {
    slug: &'static str,
    name: &'static str,
    summary: &'static str,
    /// The technique this routes to, by the slug in [`TECHNIQUES`]. A foreign
    /// key onto `techniques.slug`, so a typo here fails the seed rather than
    /// reaching a client as a route to nothing.
    technique_slug: &'static str,
    /// The goal the moment borrows. Stated per occasion rather than read back
    /// through `technique_slug`, because what a moment is for must not move
    /// when a technique's primary grouping is re-curated.
    goal: TechniqueGoal,
    surface: DeliverySurface,
    register: CopyRegister,
    /// A protocol-owned rhythm, in the technique's phase order. Empty keeps the
    /// exercise's curated durations; populated is valid only for one closed,
    /// cyclic stage and must name every phase. It carries durations and nothing
    /// else: a moment may re-time the breaths it borrows, but it cannot change
    /// where the air goes, how many phases there are, or what the copy says.
    phase_durations_ms: &'static [i32],
    /// The protocol's caution, empty where the exercise says all that needs
    /// saying. The two divide on whether the hazard is the breathing or the
    /// moment: the breathlessness triage on `when-youre-winded` and the child
    /// caution on `with-your-child` are hazards of the situation, not of the
    /// breath. `the_protocols_that_need_a_warning_carry_one` pins the set.
    safety_note: &'static str,
    /// What this occasion asks for, as a target a client fits whole cycles
    /// into rather than a stopwatch that cuts a breath short.
    duration_ms: i32,
}

/// One rung of the Start here progression.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProgressionStepSeed {
    technique_slug: &'static str,
    /// Why this one at this point — what makes the order a progression rather
    /// than a list.
    note: &'static str,
}

/// The whole of the curated reference data as JSON, each list in presentation
/// order, with a trailing newline like every other generated file. It exists so
/// the app and the drawings work from the numbers the database is seeded with.
/// It reads the four `const` lists and opens no connection. It carries the
/// occasions and the progression too, so a first launch works offline.
pub fn catalogue_json() -> Result<String> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Catalogue<'a> {
        techniques: Vec<TechniqueExport<'a>>,
        foundations: Vec<FoundationExport>,
        occasions: &'static [OccasionSeed],
        progression: &'static [ProgressionStepSeed],
        physiology: Physiology,
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct TechniqueExport<'a> {
        slug: &'static str,
        name: &'static str,
        summary: &'static str,
        mechanism: String,
        mechanism_content: ReadingContentSeed,
        evidence: String,
        evidence_content: ReadingContentSeed,
        evidence_grade: EvidenceGrade,
        safety_note: &'static str,
        preparation: String,
        preparation_content: ReadingContentSeed,
        goal: TechniqueGoal,
        stages: &'a [StageSeed],
        recommended_rounds: i32,
        requires_subscription: bool,
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct FoundationExport {
        slug: &'static str,
        question: &'static str,
        answer: String,
        answer_content: ReadingContentSeed,
    }

    /// The facts about a body that a client has to know to describe a session,
    /// carried here because Swift cannot depend on the [`physiology`] crate.
    /// `OndKit` keeps its own constant for ergonomics and asserts it against
    /// this value, which is the drift test that crate deleted, restored where
    /// it is still needed.
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Physiology {
        fast_breathing_cycle_ms: i32,
    }

    let techniques = TECHNIQUES
        .iter()
        .map(|technique| TechniqueExport {
            slug: technique.slug,
            name: technique.name,
            summary: technique.summary,
            mechanism: technique.mechanism.plain_text(),
            mechanism_content: technique.mechanism,
            evidence: technique.evidence.plain_text(),
            evidence_content: technique.evidence,
            evidence_grade: technique.evidence_grade,
            safety_note: technique.safety_note,
            preparation: technique.preparation.plain_text(),
            preparation_content: technique.preparation,
            goal: technique.goal,
            stages: technique.stages,
            recommended_rounds: technique.recommended_rounds,
            requires_subscription: technique.requires_subscription,
        })
        .collect();
    let foundations = FOUNDATIONS
        .iter()
        .map(|topic| FoundationExport {
            slug: topic.slug,
            question: topic.question,
            answer: topic.answer.plain_text(),
            answer_content: topic.answer,
        })
        .collect();

    let mut json = serde_json::to_string_pretty(&Catalogue {
        techniques,
        foundations,
        occasions: OCCASIONS,
        progression: PROGRESSION,
        physiology: Physiology {
            fast_breathing_cycle_ms: physiology::FAST_BREATHING_CYCLE_MS,
        },
    })
    .context("failed to serialise the curated reference data")?;
    json.push('\n');
    Ok(json)
}

pub async fn run(pool: &PgPool) -> Result<()> {
    let mut tx = pool
        .begin()
        .await
        .context("failed to open seed transaction")?;

    for (index, technique) in TECHNIQUES.iter().enumerate() {
        upsert_technique(&mut tx, index, technique).await?;
    }

    replace_foundations(&mut tx).await?;

    replace_routes(&mut tx).await?;

    tx.commit()
        .await
        .context("failed to commit seed transaction")?;
    tracing::info!(
        techniques = TECHNIQUES.len(),
        foundations = FOUNDATIONS.len(),
        occasions = OCCASIONS.len(),
        progression = PROGRESSION.len(),
        "reference data seeded"
    );

    Ok(())
}

/// Writes the breathing foundations as the complete curated set.
///
/// No table references a foundation slug, so the seed replaces the rows rather
/// than upserting them. Removing or merging a topic in [`FOUNDATIONS`] then
/// removes the deployed row instead of leaving an old answer available.
async fn replace_foundations(tx: &mut sqlx::PgTransaction<'_>) -> Result<()> {
    sqlx::query("DELETE FROM foundation_topics")
        .execute(&mut **tx)
        .await
        .context("failed to clear the foundation topics")?;

    for (index, topic) in FOUNDATIONS.iter().enumerate() {
        let answer = topic.answer.plain_text();
        let answer_content = serde_json::to_value(topic.answer)
            .context("failed to encode foundation reading content")?;
        sqlx::query(
            r"INSERT INTO foundation_topics
                 (slug, question, answer, answer_content, sort_order)
               VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(topic.slug)
        .bind(topic.question)
        .bind(answer)
        .bind(answer_content)
        .bind(i32::try_from(index).context("foundations are impossibly many")?)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert foundation topic `{}`", topic.slug))?;
    }

    Ok(())
}

/// Writes the occasion entries and the Start here progression, replacing both
/// wholesale. Nothing references an occasion or a step, so deleting an entry
/// from this file deletes the row. It runs after the techniques in the same
/// transaction because both tables have a foreign key onto `techniques.slug`.
async fn replace_routes(tx: &mut sqlx::PgTransaction<'_>) -> Result<()> {
    sqlx::query("DELETE FROM occasions")
        .execute(&mut **tx)
        .await
        .context("failed to clear the occasions")?;

    for (index, occasion) in OCCASIONS.iter().enumerate() {
        sqlx::query(
            r"INSERT INTO occasions
                 (slug, name, summary, technique_slug, goal, surface, register, duration_ms,
                  phase_durations_ms, safety_note, sort_order)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(occasion.slug)
        .bind(occasion.name)
        .bind(occasion.summary)
        .bind(occasion.technique_slug)
        .bind(occasion.goal)
        .bind(occasion.surface)
        .bind(occasion.register)
        .bind(occasion.duration_ms)
        .bind(occasion.phase_durations_ms)
        .bind(occasion.safety_note)
        .bind(i32::try_from(index).context("occasions are impossibly many")?)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert occasion `{}`", occasion.slug))?;
    }

    sqlx::query("DELETE FROM progression_steps")
        .execute(&mut **tx)
        .await
        .context("failed to clear the progression")?;

    for (ordinal, step) in PROGRESSION.iter().enumerate() {
        let ordinal = i32::try_from(ordinal).context("the progression is impossibly long")?;

        sqlx::query(
            r"INSERT INTO progression_steps (ordinal, technique_slug, note)
               VALUES ($1, $2, $3)",
        )
        .bind(ordinal)
        .bind(step.technique_slug)
        .bind(step.note)
        .execute(&mut **tx)
        .await
        .with_context(|| {
            format!(
                "failed to insert progression step {ordinal} (`{}`)",
                step.technique_slug
            )
        })?;
    }

    Ok(())
}

/// Writes one technique and replaces its stages wholesale.
async fn upsert_technique(
    tx: &mut sqlx::PgTransaction<'_>,
    index: usize,
    technique: &TechniqueSeed,
) -> Result<()> {
    let mechanism = technique.mechanism.plain_text();
    let evidence = technique.evidence.plain_text();
    let preparation = technique.preparation.plain_text();
    let mechanism_content = serde_json::to_value(technique.mechanism)
        .context("failed to encode mechanism reading content")?;
    let evidence_content = serde_json::to_value(technique.evidence)
        .context("failed to encode evidence reading content")?;
    let preparation_content = (!technique.preparation.is_empty())
        .then(|| serde_json::to_value(technique.preparation))
        .transpose()
        .context("failed to encode preparation reading content")?;

    // `id` is only consumed on first insert; on conflict the existing row keeps
    // its id, so reseeding never invalidates a reference held elsewhere.
    let id: String = sqlx::query_scalar(
        r"INSERT INTO techniques
                 (id, slug, name, summary, mechanism, mechanism_content, evidence,
                  evidence_content, evidence_grade, safety_note, preparation,
                  preparation_content, goal, sort_order, recommended_rounds,
                  requires_subscription)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                       $14, $15, $16)
               ON CONFLICT (slug) DO UPDATE SET
                 name = EXCLUDED.name,
                 summary = EXCLUDED.summary,
                 mechanism = EXCLUDED.mechanism,
                 mechanism_content = EXCLUDED.mechanism_content,
                 evidence = EXCLUDED.evidence,
                 evidence_content = EXCLUDED.evidence_content,
                 evidence_grade = EXCLUDED.evidence_grade,
                 safety_note = EXCLUDED.safety_note,
                 preparation = EXCLUDED.preparation,
                 preparation_content = EXCLUDED.preparation_content,
                 goal = EXCLUDED.goal,
                 sort_order = EXCLUDED.sort_order,
                 recommended_rounds = EXCLUDED.recommended_rounds,
                 requires_subscription = EXCLUDED.requires_subscription,
                 updated_at = now()
               RETURNING id",
    )
    .bind(cuid2::create_id())
    .bind(technique.slug)
    .bind(technique.name)
    .bind(technique.summary)
    .bind(mechanism)
    .bind(mechanism_content)
    .bind(evidence)
    .bind(evidence_content)
    .bind(technique.evidence_grade)
    .bind(technique.safety_note)
    .bind(preparation)
    .bind(preparation_content)
    .bind(technique.goal)
    .bind(i32::try_from(index).context("catalogue is impossibly large")?)
    .bind(technique.recommended_rounds)
    .bind(technique.requires_subscription)
    .fetch_one(&mut **tx)
    .await
    .with_context(|| format!("failed to upsert technique `{}`", technique.slug))?;

    replace_stages(tx, &id, technique).await
}

/// Replace rather than upsert: the session is an ordered list of ordered
/// lists, so a shorter edit would otherwise leave the trailing stages of the
/// previous version behind and lengthen the technique silently. The phases go
/// with them — their foreign key is the stage.
async fn replace_stages(
    tx: &mut sqlx::PgTransaction<'_>,
    id: &str,
    technique: &TechniqueSeed,
) -> Result<()> {
    sqlx::query("DELETE FROM technique_stages WHERE technique_id = $1")
        .bind(id)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to clear stages for `{}`", technique.slug))?;

    for (ordinal, stage) in technique.stages.iter().enumerate() {
        let ordinal = i32::try_from(ordinal).context("session is impossibly long")?;

        sqlx::query(
            r"INSERT INTO technique_stages (technique_id, ordinal, cycles, open_ended)
               VALUES ($1, $2, $3, $4)",
        )
        .bind(id)
        .bind(ordinal)
        .bind(stage.cycles)
        .bind(stage.open_ended)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert stage {ordinal} of `{}`", technique.slug))?;

        for (phase_ordinal, phase) in stage.phases.iter().enumerate() {
            sqlx::query(
                r"INSERT INTO technique_phases
                     (technique_id, stage_ordinal, ordinal, kind, passage, manner,
                      duration_ms, min_duration_ms, max_duration_ms,
                      turn_gap_ms, haptic_pattern, voice_script)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)",
            )
            .bind(id)
            .bind(ordinal)
            .bind(i32::try_from(phase_ordinal).context("cycle is impossibly long")?)
            .bind(phase.kind)
            .bind(phase.passage)
            .bind(phase.manner)
            .bind(phase.duration_ms)
            .bind(phase.min_duration_ms)
            .bind(phase.max_duration_ms)
            .bind(phase.turn_gap_ms)
            .bind(phase.haptic_pattern)
            .bind(phase.voice_script)
            .execute(&mut **tx)
            .await
            .with_context(|| {
                format!(
                    "failed to insert phase {phase_ordinal} of stage {ordinal} of `{}`",
                    technique.slug
                )
            })?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The only slug the client is allowed to know about by name, and the only
    /// technique in the catalogue that has stages worth calling stages.
    const WIM_HOF: &str = "wim-hof-rounds";

    /// The committed export, parsed. The tests below read it, and none cares how
    /// it was produced.
    fn exported() -> serde_json::Value {
        serde_json::from_str(&catalogue_json().expect("the catalogue serialises"))
            .expect("the export is valid JSON")
    }

    /// The export is what the app's drawings and the marketing site's are both
    /// derived from, so a technique missing from it is a technique that silently
    /// stops having a picture. Checking every slug and every phase kind rather
    /// than the count alone: a serialiser that dropped `stages` would still
    /// produce an entry per technique.
    #[test]
    fn the_export_carries_every_technique_and_every_phase() {
        let json = exported();
        let exported = json["techniques"]
            .as_array()
            .expect("the export holds a technique array");

        assert_eq!(exported.len(), TECHNIQUES.len());

        for (exported, seeded) in exported.iter().zip(TECHNIQUES) {
            assert_eq!(exported["slug"], seeded.slug);

            let stages = exported["stages"]
                .as_array()
                .expect("a technique holds a stage array");
            assert_eq!(stages.len(), seeded.stages.len(), "`{}`", seeded.slug);

            for (stage, seeded) in stages.iter().zip(seeded.stages) {
                let phases = stage["phases"]
                    .as_array()
                    .expect("a stage holds a phase array");
                assert_eq!(phases.len(), seeded.phases.len(), "`{}`", exported["slug"]);

                for (phase, seeded) in phases.iter().zip(seeded.phases) {
                    assert_eq!(phase["durationMs"], seeded.duration_ms);
                }
            }
        }
    }

    /// The bound the `turn_gap_ms` column states, checked where the export
    /// cannot reach it: the export reads these constants and never opens the
    /// database, so a gap outside the bound would ship to the app, which
    /// refuses the whole catalogue over one. Vacuous until a table is written,
    /// which is when it starts earning its place.
    #[test]
    fn every_seeded_turn_gap_is_within_its_column_bound() {
        for technique in TECHNIQUES {
            for stage in technique.stages {
                for phase in stage.phases {
                    let Some(gap) = phase.turn_gap_ms else {
                        continue;
                    };
                    assert!(
                        (0..=600).contains(&gap),
                        "`{}` authors a {gap} ms turn gap",
                        technique.slug
                    );
                }
            }
        }
    }

    /// The vocabulary the export speaks is the database's and the contract's,
    /// not Rust's. A serde rename lost here would leave the Swift side decoding
    /// `Inhale` where it expects `INHALE`, which fails at the far end of a
    /// generate step rather than here.
    #[test]
    fn the_export_speaks_the_contract_vocabulary() {
        let json = exported();

        assert_eq!(json["techniques"][0]["goal"], "CALM");
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["kind"],
            "INHALE"
        );
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][1]["kind"],
            "HOLD_IN"
        );
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["passage"],
            "NOSE"
        );
        assert_eq!(json["techniques"][0]["evidenceGrade"], "MODERATE");
        // Box breathing shapes nothing, and the key is present saying so rather
        // than absent: a key set that varies with the data is the worse artefact
        // to diff, and `Option<Manner>` without a skip is what keeps it steady.
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["manner"],
            serde_json::Value::Null
        );
        // The three cadence keys on the same terms, and null for the same
        // reason: nothing authors a cadence, and a reader taking an absent key
        // for an authored zero would drop the derived turn from every phase.
        for key in ["turnGapMs", "hapticPattern", "voiceScript"] {
            assert_eq!(
                json["techniques"][0]["stages"][0]["phases"][0].get(key),
                Some(&serde_json::Value::Null)
            );
        }
        // And one that is shaped, so the label is checked and not only the
        // absence of one — a serialiser that emitted every manner as null would
        // satisfy the line above.
        let cooling = TECHNIQUES
            .iter()
            .position(|technique| technique.slug == "cooling-breath")
            .expect("the catalogue seeds a cooling breath");
        assert_eq!(
            json["techniques"][cooling]["stages"][0]["phases"][0]["manner"],
            "CURLED_TONGUE"
        );

        // Swept rather than sampled, unlike the technique assertions above: the
        // first occasion is whichever the curation happens to lead with, so
        // naming one would break on a reorder while proving no more. A loop
        // rather than `all`, so a failure names the occasion that broke it —
        // over seventeen entries, "false is not true" is not a message.
        for occasion in json["occasions"]
            .as_array()
            .expect("the export holds an occasion array")
        {
            let surface = occasion["surface"].as_str().expect("a surface label");
            let register = occasion["register"].as_str().expect("a register label");
            assert!(
                ["FULL_SCREEN", "DISCREET"].contains(&surface),
                "`{}` exports surface `{surface}`",
                occasion["slug"]
            );
            assert!(
                ["PLAIN", "PLAYFUL"].contains(&register),
                "`{}` exports register `{register}`",
                occasion["slug"]
            );
        }
    }

    /// The routing half of the export, which nothing reads until a launch out of
    /// range needs it — and which therefore has no other chance to go wrong
    /// loudly. The seed writing the database cannot catch a mistake here: it
    /// binds these constants directly and would agree with itself whatever the
    /// serialiser did.
    #[test]
    fn the_export_carries_the_routing_layer() {
        let json = exported();

        let occasions = json["occasions"]
            .as_array()
            .expect("the export holds an occasion array");
        assert_eq!(occasions.len(), OCCASIONS.len());

        for (exported, seeded) in occasions.iter().zip(OCCASIONS) {
            assert_eq!(exported["slug"], seeded.slug);
            assert_eq!(exported["techniqueSlug"], seeded.technique_slug);
            assert_eq!(exported["durationMs"], seeded.duration_ms);
            assert_eq!(
                exported["phaseDurationsMs"],
                serde_json::json!(seeded.phase_durations_ms),
                "`{}`",
                seeded.slug
            );
        }

        let foundations = json["foundations"]
            .as_array()
            .expect("the export holds a foundation array");
        assert_eq!(foundations.len(), FOUNDATIONS.len());
        for (exported, seeded) in foundations.iter().zip(FOUNDATIONS) {
            assert_eq!(exported["slug"], seeded.slug);
            assert_eq!(exported["answer"], seeded.answer.plain_text());
            assert_eq!(
                exported["answerContent"],
                serde_json::to_value(seeded.answer).expect("reading content serialises")
            );
        }

        let progression = json["progression"]
            .as_array()
            .expect("the export holds a progression array");
        assert_eq!(progression.len(), PROGRESSION.len());
        for (exported, seeded) in progression.iter().zip(PROGRESSION) {
            assert_eq!(exported["techniqueSlug"], seeded.technique_slug);
        }
    }

    /// The invariant the `passage` column's `CHECK` states, asserted over the
    /// export because that is the copy the drawings and the marketing site read:
    /// a breath always says where the air goes, and a hold never does, because
    /// air that is not moving goes nowhere.
    #[test]
    fn every_breath_names_a_passage_and_no_hold_does() {
        for technique in TECHNIQUES {
            for stage in technique.stages {
                for phase in stage.phases {
                    let breathing = phase.kind.is_breathing();
                    assert_eq!(
                        breathing,
                        phase.passage.is_some(),
                        "`{}` has a {:?} phase whose passage does not match",
                        technique.slug,
                        phase.kind
                    );
                }
            }
        }
    }

    /// The nostrils are the exercise rather than a decoration on it: without
    /// them alternate-nostril breathing is a 4:6:4:6 rhythm, which the catalogue
    /// already holds twice over. Seeded here rather than asserted by a
    /// client-side table keyed on this slug, which is what it was until the
    /// column existed.
    #[test]
    fn alternate_nostril_alternates() {
        let technique = technique("alternate-nostril");

        assert_eq!(
            technique.stages[0]
                .phases
                .iter()
                .map(|phase| phase.passage)
                .collect::<Vec<_>>(),
            vec![
                Some(Passage::LeftNostril),
                Some(Passage::RightNostril),
                Some(Passage::RightNostril),
                Some(Passage::LeftNostril),
            ]
        );
    }

    /// The catalogue is free throughout. A `requires_subscription` typed into
    /// one struct reads as a decision somebody made rather than the typo it is,
    /// so what this pins is that no technique is singled out.
    #[test]
    fn no_technique_is_behind_a_subscription() {
        let gated: Vec<_> = TECHNIQUES
            .iter()
            .filter(|technique| technique.requires_subscription)
            .map(|technique| technique.slug)
            .collect();

        assert!(
            gated.is_empty(),
            "the catalogue is free at every technique, and these are not: {gated:?}"
        );
    }

    /// A `safety_note` is a hazard that arrives mid-breath, and the consent for
    /// it lives in onboarding. [`PROGRESSION`] is the one route that asks the
    /// person to decide nothing, so nothing on it may carry a note. The three
    /// that do are each reached by a choice, and the phone stands the note up as
    /// a full-screen warning before the countdown; the watch does not yet.
    #[test]
    fn the_progression_cannot_go_wrong() {
        for step in PROGRESSION {
            let technique = technique(step.technique_slug);

            assert!(
                technique.safety_note.is_empty(),
                "`{}` is on the progression and carries a safety note",
                technique.slug
            );
        }
    }

    /// Every seeded technique opens with a lead and no more than three useful
    /// points. The client falls back to the legacy text when structure is
    /// absent, so the seed also keeps that derived projection complete.
    #[test]
    fn every_technique_opens_on_its_mechanism() {
        for technique in TECHNIQUES {
            assert_reading_content(technique.slug, technique.mechanism);
            assert!(
                technique.mechanism.items.len() <= 3,
                "`{}` needs at most three mechanism points",
                technique.slug
            );
        }
    }

    /// Every seeded technique keeps its candid evidence visible as a verdict
    /// followed by two or three scannable findings.
    #[test]
    fn every_technique_names_its_evidence() {
        for technique in TECHNIQUES {
            assert_reading_content(technique.slug, technique.evidence);
            assert!(
                (2..=3).contains(&technique.evidence.items.len()),
                "`{}` needs two or three evidence points",
                technique.slug
            );
            assert_eq!(technique.evidence.list_style, ReadingListStyle::Bullets);
        }
    }

    fn assert_reading_content(owner: &str, content: ReadingContentSeed) {
        assert!(!content.lead.is_empty(), "`{owner}` needs a reading lead");
        assert!(
            content.items.iter().all(|item| !item.is_empty()),
            "`{owner}` carries an empty reading item"
        );
        assert_eq!(
            content.items.is_empty(),
            content.list_style == ReadingListStyle::None,
            "`{owner}` has items and list style out of step"
        );
        assert!(
            !content.plain_text().is_empty(),
            "`{owner}` has no fallback"
        );
    }

    /// The grade is the evidence paragraph in one word, so a catalogue that sits
    /// on one rung tells a reader nothing about the row they are looking at. The
    /// field is an enum of two values, so drifting to one is how it goes wrong.
    #[test]
    fn the_catalogue_grades_its_evidence_both_ways() {
        let moderate = TECHNIQUES
            .iter()
            .filter(|technique| technique.evidence_grade == EvidenceGrade::Moderate)
            .count();

        assert!(
            moderate > 0,
            "nothing in the catalogue is moderately evidenced"
        );
        assert!(
            moderate < TECHNIQUES.len(),
            "every technique claims moderate evidence, which no breathing catalogue can"
        );
    }

    /// A technique with no stages — or a stage with no phases — would leave the
    /// client with an empty animation loop and nothing to advance through. The
    /// service rejects both at read time; catching it here names the technique.
    #[test]
    fn every_technique_is_a_playable_session() {
        for technique in TECHNIQUES {
            assert!(
                !technique.stages.is_empty(),
                "`{}` has no stages",
                technique.slug
            );
            assert!(
                technique.recommended_rounds > 0,
                "`{}` recommends no rounds",
                technique.slug
            );

            for (ordinal, stage) in technique.stages.iter().enumerate() {
                assert!(
                    !stage.phases.is_empty(),
                    "stage {ordinal} of `{}` has no phases",
                    technique.slug
                );
                assert!(
                    stage.cycles > 0,
                    "stage {ordinal} of `{}` plays no cycles",
                    technique.slug
                );
            }
        }
    }

    /// The dose convention documented on [`TECHNIQUES`], enforced so a new
    /// technique declares a band rather than inheriting one. Four bands are in
    /// use: a five-minute sitting, an under-a-minute reset or fast bout,
    /// `four-seven-eight`'s eight-round tradition, and `pursed-lip-breathing`'s
    /// three minutes. `wim-hof-rounds` has none: the person ends its retention.
    #[test]
    fn every_technique_runs_the_dose_it_was_given() {
        /// The band each technique's planned session must land in, in seconds,
        /// or `None` where the person ends the stage and there is nothing to
        /// measure.
        const DOSES: &[(&str, Option<(i64, i64)>)] = &[
            ("box-breathing", Some((270, 330))),
            ("coherent-breathing", Some((270, 330))),
            ("four-seven-eight", Some((120, 180))),
            ("extended-exhale", Some((270, 330))),
            ("physiological-sigh", Some((0, 90))),
            ("cyclic-sighing", Some((270, 330))),
            ("pursed-lip-breathing", Some((150, 210))),
            ("humming-breath", Some((270, 330))),
            ("cooling-breath", Some((270, 330))),
            ("bellows-breath", Some((0, 90))),
            (WIM_HOF, None),
            ("long-box-breathing", Some((270, 330))),
            ("alternate-nostril", Some((270, 330))),
        ];

        for technique in TECHNIQUES {
            let decided = DOSES
                .iter()
                .find(|(slug, _)| *slug == technique.slug)
                .unwrap_or_else(|| panic!("`{}` has no decided dose", technique.slug));

            let Some((low, high)) = decided.1 else {
                continue;
            };
            let seconds = planned_seconds(technique);
            assert!(
                (low..=high).contains(&seconds),
                "`{}` runs {seconds}s, outside the {low}–{high}s it was given",
                technique.slug
            );
        }
    }

    /// The whole session a technique plans, in seconds — every stage's cycles
    /// at its own phase durations, which is the sum the clients compute too.
    fn planned_seconds(technique: &TechniqueSeed) -> i64 {
        technique
            .stages
            .iter()
            .map(|stage| {
                let cycle: i64 = stage.phases.iter().map(|p| i64::from(p.duration_ms)).sum();
                cycle * i64::from(stage.cycles)
            })
            .sum::<i64>()
            / 1000
    }

    /// `slug` is the key the iOS client pins its artwork and haptics to, and the
    /// upsert is keyed on it — a duplicate would make the seed order decide
    /// which definition wins.
    #[test]
    fn slugs_are_unique() {
        let mut seen = std::collections::HashSet::new();
        for technique in TECHNIQUES {
            assert!(
                seen.insert(technique.slug),
                "duplicate slug `{}`",
                technique.slug
            );
        }
    }

    /// The `technique_phases_duration_within_range` CHECK in `0003` would reject
    /// these at write time, and a client rendering a dial from a range that does
    /// not contain its own starting value has nowhere to put the handle.
    #[test]
    fn every_dial_range_contains_its_default() {
        for technique in TECHNIQUES {
            for stage in technique.stages {
                for phase in stage.phases {
                    assert!(
                        phase.min_duration_ms > 0,
                        "`{}` has a non-positive {:?} minimum",
                        technique.slug,
                        phase.kind
                    );
                    assert!(
                        phase.min_duration_ms <= phase.duration_ms
                            && phase.duration_ms <= phase.max_duration_ms,
                        "`{}` has a {:?} default of {}ms outside its {}–{}ms range",
                        technique.slug,
                        phase.kind,
                        phase.duration_ms,
                        phase.min_duration_ms,
                        phase.max_duration_ms
                    );
                }
            }
        }
    }

    /// An open-ended stage stops the session clock until the person taps, so one
    /// seeded by accident strands them on a screen that never advances. The Wim
    /// Hof retention is the only place it belongs, and it is one emptied-lung
    /// hold. It is entered on an exhale and left on an inhale, and neither
    /// breath may sit inside the stage, whose clock never ends.
    #[test]
    fn only_the_wim_hof_retention_is_open_ended() {
        for technique in TECHNIQUES {
            for (ordinal, stage) in technique.stages.iter().enumerate() {
                if !stage.open_ended {
                    continue;
                }

                assert_eq!(
                    technique.slug, WIM_HOF,
                    "`{}` has an unexpected open-ended stage",
                    technique.slug
                );
                assert_eq!(
                    stage.phases.len(),
                    1,
                    "the open-ended stage of `{}` is more than one hold",
                    technique.slug
                );
                assert_eq!(stage.phases[0].kind, PhaseKind::HoldOut);
                assert_eq!(stage.cycles, 1, "an open-ended stage repeats nothing");

                let before = technique.stages[..ordinal]
                    .last()
                    .and_then(|stage| stage.phases.last())
                    .map(|phase| phase.kind);
                assert_eq!(
                    before,
                    Some(PhaseKind::Exhale),
                    "the retention in `{}` is entered on nothing",
                    technique.slug
                );

                let after = technique
                    .stages
                    .get(ordinal + 1)
                    .and_then(|stage| stage.phases.first())
                    .map(|phase| phase.kind);
                assert_eq!(
                    after,
                    Some(PhaseKind::Inhale),
                    "the retention in `{}` is never breathed out of",
                    technique.slug
                );
            }
        }

        let wim_hof = technique(WIM_HOF);

        assert!(
            wim_hof.stages.iter().any(|stage| stage.open_ended),
            "the retention lost its open-ended flag"
        );
    }

    /// The blackout rule as structure rather than prose: in a technique that
    /// breathes fast anywhere in it, a timed hold long enough to be a target is
    /// forbidden. The hold is either no longer than
    /// [`physiology::TIMED_HOLD_CEILING_MS`], or open-ended so the person ends
    /// it. `docs/product/breathing-science.md` §7 rule 9 carries the rest.
    #[test]
    fn no_hold_after_fast_breathing_is_a_target() {
        for technique in TECHNIQUES {
            if !breathes_fast_at_the_floor(technique, &[]) {
                continue;
            }

            for (ordinal, stage) in technique.stages.iter().enumerate() {
                if stage.open_ended {
                    continue;
                }

                for phase in stage.phases {
                    if phase.kind.is_breathing() {
                        continue;
                    }

                    // The ceiling is on the dial's top rather than the default:
                    // a hold that only becomes a feat once somebody turns it up
                    // is still a feat the catalogue offered them.
                    assert!(
                        !physiology::is_a_timed_target(phase.max_duration_ms),
                        "stage {ordinal} of `{}` times a hold up to {}ms after fast breathing — \
                         hold it to {}ms or less, or let the person end it",
                        technique.slug,
                        phase.max_duration_ms,
                        physiology::TIMED_HOLD_CEILING_MS
                    );
                }
            }
        }
    }

    /// The shaped breaths are the three decided, asserted in both directions. A
    /// manner that appears tells somebody mid-session how to breathe on a
    /// technique nobody wrote that copy for; a manner that disappears reverts
    /// the technique to a plain breath. The triple is pinned rather than the
    /// slug, because a manner on the wrong phase reads correctly in a diff.
    #[test]
    fn the_breaths_that_are_shaped_are_the_three_decided() {
        let shaped: Vec<_> = TECHNIQUES
            .iter()
            .flat_map(|technique| {
                technique.stages.iter().flat_map(move |stage| {
                    stage.phases.iter().filter_map(move |phase| {
                        phase.manner.map(|m| (technique.slug, phase.kind, m))
                    })
                })
            })
            .collect();

        assert_eq!(
            shaped,
            vec![
                (
                    "pursed-lip-breathing",
                    PhaseKind::Exhale,
                    Manner::PursedLips
                ),
                ("humming-breath", PhaseKind::Exhale, Manner::Hum),
                ("cooling-breath", PhaseKind::Inhale, Manner::CurledTongue),
            ]
        );
    }

    /// Every shaped breath also says how to make the shape. `Manner` names one
    /// shape and cannot hedge, so a shaped technique with an empty preparation
    /// leaves "through a curled tongue" as the only instruction anybody reads,
    /// which for a large minority is one they cannot follow. The cooling breath
    /// keeps its alternative for a tongue that will not roll.
    #[test]
    fn the_shaped_techniques_prepare_their_shape() {
        // Stated as the rule rather than as a list of the four that satisfy it
        // today: a fourteenth shaped technique with nothing to prepare should
        // fail by naming what it broke, not by diffing a list of slugs.
        for technique in TECHNIQUES {
            let shaped = technique
                .stages
                .iter()
                .any(|stage| stage.phases.iter().any(|phase| phase.manner.is_some()));
            assert!(
                !shaped || !technique.preparation.is_empty(),
                "`{}` shapes a breath and never says how to make the shape",
                technique.slug
            );
        }

        let cooling = TECHNIQUES
            .iter()
            .find(|technique| technique.slug == "cooling-breath")
            .expect("the catalogue seeds a cooling breath");
        assert!(
            cooling.preparation.plain_text().contains("teeth"),
            "the cooling breath stopped offering an alternative to the curl"
        );
    }

    /// Every technique with a safety note still names its own fainting hazard.
    /// Phrases are pinned rather than sentences: the wording may be improved,
    /// the hazards may not disappear. Asserted in both directions — a missing
    /// note loses a warning at the moment of risk, and an extra one interrupts
    /// a session with advice the consent screen already gave.
    #[test]
    fn the_techniques_that_need_a_warning_carry_one() {
        let carry_a_note: Vec<_> = TECHNIQUES
            .iter()
            .filter(|technique| !technique.safety_note.is_empty())
            .map(|technique| technique.slug)
            .collect();
        assert_eq!(carry_a_note, vec!["bellows-breath", WIM_HOF]);

        for slug in [WIM_HOF, "bellows-breath"] {
            let technique = technique(slug);

            for phrase in ["water", "driv"] {
                assert!(
                    technique.safety_note.contains(phrase),
                    "`{slug}` no longer warns about `{phrase}`"
                );
            }
        }
    }

    /// The cautions a route carries rather than its exercise, pinned in both
    /// directions as the technique notes above are, and by phrase for the same
    /// reason. A note belongs here when the hazard is the moment and not the
    /// breathing, and neither exercise may collect the other's note.
    /// `docs/product/breathing-science.md` §3.14 and §7 rule 3 carry the rest.
    #[test]
    fn the_protocols_that_need_a_warning_carry_one() {
        /// Each warned route, in seed order, and the hazards its note must
        /// still name.
        const WARNED: &[(&str, &[&str])] = &[
            ("when-youre-winded", &["doctor", "severe", "emergency"]),
            (
                "when-you-cant-get-a-satisfying-breath",
                &["doctor", "severe", "emergency"],
            ),
            ("with-your-child", &["hold", "fast"]),
        ];

        let carry_a_note: Vec<_> = OCCASIONS
            .iter()
            .filter(|occasion| !occasion.safety_note.is_empty())
            .map(|occasion| occasion.slug)
            .collect();
        assert_eq!(
            carry_a_note,
            WARNED.iter().map(|(slug, _)| *slug).collect::<Vec<_>>()
        );

        for (slug, hazards) in WARNED {
            let warned = occasion(slug);

            for hazard in *hazards {
                assert!(
                    warned.safety_note.contains(hazard),
                    "`{slug}` no longer warns about `{hazard}`"
                );
            }
        }

        let panic = occasion("when-panic-is-rising");
        assert!(
            panic.safety_note.is_empty(),
            "a full-screen warning is the one thing not to put in front of this route"
        );
        for instruction in ["Small, quiet breaths", "not deep"] {
            assert!(
                panic.summary.contains(instruction),
                "`when-panic-is-rising` no longer says `{instruction}`"
            );
        }
    }

    /// No occasion framed as anything but energy may resolve to a technique that
    /// breathes fast. The constituency this protects — about one adult in ten,
    /// already breathing in a symptom-generating pattern — is in
    /// `docs/product/breathing-science.md` §6.7, and the fence is §7 rule 1. The
    /// goal is matched rather than the wording, which is what gets rewritten.
    #[test]
    fn no_route_but_an_energising_one_reaches_fast_breathing() {
        for occasion in OCCASIONS {
            if occasion.goal == TechniqueGoal::Energy {
                continue;
            }

            let technique = technique(occasion.technique_slug);
            // Through the protocol's own rhythm, because a protocol is not
            // bounded by the exercise's dial: `with-your-child` runs Extended
            // Exhale at a five-second exhale, a second under the floor the
            // standalone exercise offers. Reading the technique alone would
            // wave through the one kind of route that can outrun its exercise.
            assert!(
                !breathes_fast_at_the_floor(technique, occasion.phase_durations_ms),
                "`{}` asks for {:?} and routes to `{}`, which can be breathed fast — \
                 fast breathing is reachable from an energising frame only",
                occasion.slug,
                occasion.goal,
                technique.slug
            );
        }
    }

    /// Whether any stage can be breathed fast at the fastest anybody can reach.
    /// `rhythm_ms` is a protocol's own phase durations, positional, and empty
    /// means the exercise alone; each phase takes the lower of dial floor and
    /// prescription, for the reason in `docs/product/breathing-science.md` §7
    /// rule 1. A stage that never breathes is not fast however short it is.
    fn breathes_fast_at_the_floor(technique: &TechniqueSeed, rhythm_ms: &[i32]) -> bool {
        technique.stages.iter().any(|stage| {
            let cycle_ms: i32 = stage
                .phases
                .iter()
                .enumerate()
                .map(|(index, phase)| match rhythm_ms.get(index) {
                    Some(prescribed) => phase.min_duration_ms.min(*prescribed),
                    None => phase.min_duration_ms,
                })
                .sum();
            stage.phases.iter().any(|phase| phase.kind.is_breathing())
                && physiology::breathes_fast(cycle_ms)
        })
    }

    /// The technique a slug names.
    fn technique(slug: &str) -> &'static TechniqueSeed {
        TECHNIQUES
            .iter()
            .find(|technique| technique.slug == slug)
            .unwrap_or_else(|| panic!("the catalogue holds `{slug}`"))
    }

    /// The occasion a slug names.
    fn occasion(slug: &str) -> &'static OccasionSeed {
        OCCASIONS
            .iter()
            .find(|occasion| occasion.slug == slug)
            .unwrap_or_else(|| panic!("the working set holds `{slug}`"))
    }

    /// What an occasion resolves to: the route it takes, the framing it wears,
    /// and the dose it asks for.
    type Resolution = (
        &'static str,
        &'static str,
        TechniqueGoal,
        DeliverySurface,
        CopyRegister,
        &'static [i32],
        i32,
    );

    /// Every occasion's resolution, in seed order — the decision itself
    /// (TIM-60, D1), kept as data beside the test that pins it.
    const DECIDED: &[Resolution] = &[
        (
            "five-minutes-today",
            "cyclic-sighing",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "ten-quiet-minutes",
            "coherent-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            600_000,
        ),
        (
            "before-a-presentation",
            "box-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            180_000,
        ),
        (
            "after-a-hard-meeting",
            "coherent-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "through-this-meeting",
            "coherent-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "after-a-workout",
            "extended-exhale",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            180_000,
        ),
        (
            "when-youre-winded",
            "pursed-lip-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            120_000,
        ),
        (
            "when-you-cant-get-a-satisfying-breath",
            "extended-exhale",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "when-panic-is-rising",
            "extended-exhale",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[2500, 4500],
            180_000,
        ),
        (
            "in-a-tight-spot",
            "extended-exhale",
            TechniqueGoal::Calm,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "overloaded-and-need-quiet",
            "box-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            180_000,
        ),
        (
            "feeling-queasy",
            "coherent-breathing",
            TechniqueGoal::Calm,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            180_000,
        ),
        (
            "winding-down",
            "extended-exhale",
            TechniqueGoal::Sleep,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "awake-at-3am",
            "extended-exhale",
            TechniqueGoal::Sleep,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            300_000,
        ),
        (
            "with-your-child",
            "extended-exhale",
            TechniqueGoal::Calm,
            DeliverySurface::FullScreen,
            CopyRegister::Playful,
            &[3000, 5000],
            90_000,
        ),
        (
            "a-moment-to-reset",
            "physiological-sigh",
            TechniqueGoal::Reset,
            DeliverySurface::FullScreen,
            CopyRegister::Plain,
            &[],
            60_000,
        ),
        (
            "riding-out-a-craving",
            "extended-exhale",
            TechniqueGoal::Reset,
            DeliverySurface::Discreet,
            CopyRegister::Plain,
            &[],
            180_000,
        ),
    ];

    /// What each occasion resolves to, pinned end to end. A route that moves to
    /// another technique, borrows another goal, changes how loudly it runs, or
    /// starts speaking in another register is a different product answer under
    /// the same name, and nothing else in the tree would notice.
    #[test]
    fn the_seeded_occasions_resolve_as_decided() {
        let resolved: Vec<Resolution> = OCCASIONS
            .iter()
            .map(|occasion| {
                (
                    occasion.slug,
                    occasion.technique_slug,
                    occasion.goal,
                    occasion.surface,
                    occasion.register,
                    occasion.phase_durations_ms,
                    occasion.duration_ms,
                )
            })
            .collect();

        assert_eq!(resolved, DECIDED);
    }

    /// The surface is what makes an occasion more than a second name for a goal:
    /// each pair is the same technique, at the same pace, for the same time,
    /// differing only in whether anybody in the room could tell. Membership is
    /// [`OCCASIONS`]'s doc comment, never a search for coincidences — enrolling
    /// one freezes together two doses that were curated apart.
    #[test]
    fn every_surface_pair_differs_only_in_its_surface() {
        /// The discreet entry and the full-screen one it is otherwise identical
        /// to, in that order.
        const PAIRS: &[(&str, &str)] = &[
            ("through-this-meeting", "after-a-hard-meeting"),
            ("awake-at-3am", "winding-down"),
        ];

        for (quiet_slug, loud_slug) in PAIRS {
            let quiet = occasion(quiet_slug);
            let loud = occasion(loud_slug);

            assert_eq!(
                quiet.technique_slug, loud.technique_slug,
                "`{quiet_slug}` and `{loud_slug}` no longer breathe the same exercise"
            );
            assert_eq!(
                quiet.goal, loud.goal,
                "`{quiet_slug}` and `{loud_slug}` no longer ask for the same thing"
            );
            assert_eq!(
                quiet.duration_ms, loud.duration_ms,
                "`{quiet_slug}` and `{loud_slug}` no longer run for the same time"
            );
            assert_eq!(
                quiet.surface,
                DeliverySurface::Discreet,
                "`{quiet_slug}` is the quiet half of its pair"
            );
            assert_eq!(
                loud.surface,
                DeliverySurface::FullScreen,
                "`{loud_slug}` is the full-screen half of its pair"
            );
        }
    }

    /// A route can replace a rhythm only where phase order has one unambiguous
    /// meaning. The protocol is curated beside the catalogue, so a bad shape is
    /// a seed error rather than something every client should reinterpret.
    #[test]
    fn every_protocol_rhythm_fits_its_exercise() {
        for occasion in OCCASIONS
            .iter()
            .filter(|occasion| !occasion.phase_durations_ms.is_empty())
        {
            let technique = technique(occasion.technique_slug);
            assert_eq!(
                technique.stages.len(),
                1,
                "`{}` overrides a staged exercise",
                occasion.slug
            );
            let stage = &technique.stages[0];
            assert!(
                !stage.open_ended,
                "`{}` overrides an open-ended exercise",
                occasion.slug
            );
            assert_eq!(
                occasion.phase_durations_ms.len(),
                stage.phases.len(),
                "`{}` does not name every phase",
                occasion.slug
            );
            assert!(
                occasion
                    .phase_durations_ms
                    .iter()
                    .all(|duration| *duration > 0),
                "`{}` carries a non-positive phase duration",
                occasion.slug
            );
        }
    }

    /// A playful route may only name an exercise its words can describe: breath
    /// that moves, through the nose, nothing held. A hold would put "smell the
    /// flower" on the one thing the child protocol's safety note tells a parent
    /// not to teach. The proto scopes the playful register to nose breaths, so
    /// any other passage falls back to the plain wording mid-session.
    #[test]
    fn a_playful_route_names_an_exercise_its_words_can_describe() {
        let playful = OCCASIONS
            .iter()
            .filter(|occasion| occasion.register == CopyRegister::Playful);

        for occasion in playful {
            let slug = occasion.technique_slug;

            for phase in technique(slug).stages.iter().flat_map(|stage| stage.phases) {
                assert!(
                    phase.kind.is_breathing(),
                    "`{slug}` is spoken playfully and holds the breath"
                );
                assert_eq!(
                    phase.passage,
                    Some(Passage::Nose),
                    "`{slug}` is spoken playfully and breathes somewhere the words cannot name"
                );
            }
        }
    }

    /// Why `goal` sits on the occasion rather than being read off the technique.
    /// Extended exhale is grouped under sleep, and coming down from a workout is
    /// not going to bed. On home only: `DialStop.goal` wears the occasion's and
    /// the session it starts wears `technique.goal`, because `HomeView.begin(_:)`
    /// hands on the technique and the dose and drops the framing (TIM-139).
    #[test]
    fn the_workout_occasion_borrows_a_goal_its_technique_does_not_have() {
        let workout = occasion("after-a-workout");

        assert_eq!(workout.goal, TechniqueGoal::Calm);
        assert_ne!(workout.goal, technique(workout.technique_slug).goal);
    }

    /// Both route tables carry a foreign key onto `techniques.slug`, so a typo
    /// fails the seed rather than reaching a client — but it fails it with a
    /// constraint name at the far end of a `mise run migrate`. This names the
    /// entry, with no database in reach.
    #[test]
    fn every_route_ends_in_a_technique_the_catalogue_holds() {
        let routed = OCCASIONS
            .iter()
            .map(|occasion| occasion.technique_slug)
            .chain(PROGRESSION.iter().map(|step| step.technique_slug));

        for slug in routed {
            assert!(
                TECHNIQUES.iter().any(|technique| technique.slug == slug),
                "a route points at `{slug}`, which the catalogue does not hold"
            );
        }
    }

    /// The progression is an ordering over *part* of the catalogue, which is
    /// the shape "suggestive, never gating" takes in data (TIM-60, D2): a
    /// technique's absence from this list is not a lock, and a technique that
    /// appeared twice would be a loop rather than a progression.
    #[test]
    fn the_progression_orders_part_of_the_catalogue() {
        assert!(
            !PROGRESSION.is_empty(),
            "a progression with no first step is not a landing place"
        );
        assert!(
            PROGRESSION.len() < TECHNIQUES.len(),
            "a progression naming every technique is the catalogue in another order"
        );

        let mut seen = std::collections::HashSet::new();
        for step in PROGRESSION {
            assert!(
                seen.insert(step.technique_slug),
                "`{}` appears twice in the progression",
                step.technique_slug
            );
            assert!(
                !step.note.is_empty(),
                "`{}` is a step with no reason to be one",
                step.technique_slug
            );
        }
    }

    /// The client and the assistant cite foundations by slug, so the canonical
    /// set needs stable, unique keys even though the seed replaces it wholesale.
    #[test]
    fn foundations_are_canonical_and_structured() {
        const EXPECTED: &[&str] = &[
            "what-matters-most",
            "what-a-good-breath-feels-like",
            "is-a-deep-breath-the-answer",
            "why-it-works",
            "belly-or-chest",
            "nose-or-mouth",
            "how-slow",
            "fast-breathing-and-holds",
            "getting-comfortable",
            "how-long",
            "when-breathing-is-the-problem",
            "how-good-is-the-evidence",
            "why-no-scores",
        ];

        let mut seen = std::collections::HashSet::new();
        for topic in FOUNDATIONS {
            assert!(seen.insert(topic.slug), "duplicate slug `{}`", topic.slug);
            assert!(!topic.question.is_empty(), "`{}` asks nothing", topic.slug);
            assert!(!topic.answer.is_empty(), "`{}` answers nothing", topic.slug);

            assert_reading_content(topic.slug, topic.answer);
        }

        assert_eq!(
            FOUNDATIONS
                .iter()
                .map(|topic| topic.slug)
                .collect::<Vec<_>>(),
            EXPECTED
        );
    }
}
