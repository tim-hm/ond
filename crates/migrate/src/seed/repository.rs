//! Every statement the seed runs, in one transaction. Runtime `sqlx::query`
//! rather than the checked macros, because this crate runs before the schema
//! exists. Each list is replaced whole, so a removed entry leaves no row.

use anyhow::{Context, Result};
use sqlx::PgPool;

use super::catalogue::{FOUNDATIONS, OCCASIONS, PROGRESSION, TECHNIQUES};
use super::types::TechniqueSeed;

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
                      turn_gap_ms, haptic_pattern)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
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
