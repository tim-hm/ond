//! Technique SQL.

use sqlx::PgPool;
use sqlx::types::Json;

use super::errors::TechniqueError;
use super::types::{
    CopyRegister, DeliverySurface, EvidenceGrade, Manner, Passage, PhaseKind, ReadingContent,
    TechniqueGoal,
};

/// A technique without its stages.
pub struct TechniqueRow {
    pub id: String,
    pub slug: String,
    pub name: String,
    pub summary: String,
    /// Why it works, as curated copy — empty for a technique nobody has written
    /// it for yet. Read only on the way to a client; nothing server-side asks.
    pub mechanism: String,
    pub mechanism_content: Option<Json<ReadingContent>>,
    /// How strong the case for it is, as curated copy — empty for an exercise
    /// nobody has written one for. Read only on the way to a client, like
    /// `mechanism`.
    pub evidence: String,
    pub evidence_content: Option<Json<ReadingContent>>,
    /// The paragraph above in one word, or `None` for a row nobody has graded.
    /// Every seeded technique carries one, so the `None` arm is what a future
    /// entry seeded ungraded would take — not the exercises people write
    /// themselves, which are not in this table.
    pub evidence_grade: Option<EvidenceGrade>,
    pub safety_note: String,
    /// What to do before the first breath — empty for all but four techniques.
    /// Read only on the way to a client, like `mechanism`.
    pub preparation: String,
    pub preparation_content: Option<Json<ReadingContent>>,
    pub goal: TechniqueGoal,
    pub recommended_rounds: i32,
    /// Whether breathing this one needs a subscription. Carried to the client
    /// and enforced only there — see the field note in the proto.
    pub requires_subscription: bool,
}

/// One stage, carrying the id of the technique it belongs to so the caller can
/// group without a second lookup.
pub struct StageRow {
    pub technique_id: String,
    pub ordinal: i32,
    pub cycles: i32,
    pub open_ended: bool,
}

/// One phase, carrying the stage it belongs to for the same reason.
pub struct PhaseRow {
    pub technique_id: String,
    pub stage_ordinal: i32,
    pub kind: PhaseKind,
    /// `None` exactly when `kind` is a hold, which the column's `CHECK` is what
    /// makes true rather than a convention this struct hopes for.
    pub passage: Option<Passage>,
    /// `None` for most phases, and never on a hold — which the column's
    /// `CHECK` states by naming a breathing kind in every arm.
    pub manner: Option<Manner>,
    pub duration_ms: i32,
    pub min_duration_ms: i32,
    pub max_duration_ms: i32,
}

pub struct FoundationTopicRow {
    pub slug: String,
    pub question: String,
    pub answer: String,
    pub answer_content: Option<Json<ReadingContent>>,
}

/// One occasion and the prescription it resolves to.
///
/// `technique_slug` is a foreign key onto `techniques.slug` rather than a
/// surrogate id, so the route arrives already speaking the key a client
/// navigates by and this read needs no join.
pub struct OccasionRow {
    pub slug: String,
    pub name: String,
    pub summary: String,
    pub technique_slug: String,
    pub goal: TechniqueGoal,
    pub surface: DeliverySurface,
    pub register: CopyRegister,
    pub duration_ms: i32,
    pub phase_durations_ms: Vec<i32>,
    pub safety_note: String,
}

/// One rung of the Start here progression, in curated order.
pub struct ProgressionStepRow {
    pub technique_slug: String,
    pub note: String,
}

/// Lists techniques in curated presentation order.
pub async fn list_techniques(pool: &PgPool) -> Result<Vec<TechniqueRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        TechniqueRow,
        r#"SELECT
            id,
            slug,
            name,
            summary,
            mechanism,
            mechanism_content AS "mechanism_content: Json<ReadingContent>",
            evidence,
            evidence_content AS "evidence_content: Json<ReadingContent>",
            evidence_grade AS "evidence_grade: EvidenceGrade",
            safety_note,
            preparation,
            preparation_content AS "preparation_content: Json<ReadingContent>",
            goal AS "goal: TechniqueGoal",
            recommended_rounds,
            requires_subscription
         FROM techniques
         ORDER BY sort_order"#
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Lists every stage of every technique, grouped by technique and in play order.
///
/// One query for the whole catalogue rather than one per technique, for the same
/// reason as the phases below: the catalogue is small and unpaginated, so the
/// per-technique variant would be a textbook N+1 for no benefit.
pub async fn list_all_stages(pool: &PgPool) -> Result<Vec<StageRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        StageRow,
        r"SELECT technique_id, ordinal, cycles, open_ended
          FROM technique_stages
          ORDER BY technique_id, ordinal"
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Lists every phase of every technique, grouped by stage and in cycle order.
pub async fn list_all_phases(pool: &PgPool) -> Result<Vec<PhaseRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        PhaseRow,
        r#"SELECT
            technique_id,
            stage_ordinal,
            kind AS "kind: PhaseKind",
            passage AS "passage: Passage",
            manner AS "manner: Manner",
            duration_ms,
            min_duration_ms,
            max_duration_ms
         FROM technique_phases
         ORDER BY technique_id, stage_ordinal, ordinal"#
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Lists the occasion entries in curated presentation order.
pub async fn list_occasions(pool: &PgPool) -> Result<Vec<OccasionRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        OccasionRow,
        r#"SELECT
            slug,
            name,
            summary,
            technique_slug,
            goal AS "goal: TechniqueGoal",
            surface AS "surface: DeliverySurface",
            register AS "register: CopyRegister",
            duration_ms,
            phase_durations_ms,
            safety_note
         FROM occasions
         ORDER BY sort_order"#
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Lists the Start here progression in curated order.
pub async fn list_progression_steps(
    pool: &PgPool,
) -> Result<Vec<ProgressionStepRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        ProgressionStepRow,
        r"SELECT technique_slug, note
          FROM progression_steps
          ORDER BY ordinal"
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Lists the breathing foundations in curated reading order.
pub async fn list_foundation_topics(
    pool: &PgPool,
) -> Result<Vec<FoundationTopicRow>, TechniqueError> {
    let rows = sqlx::query_as!(
        FoundationTopicRow,
        r#"SELECT slug, question, answer,
                  answer_content AS "answer_content: Json<ReadingContent>"
          FROM foundation_topics
          ORDER BY sort_order"#
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}
