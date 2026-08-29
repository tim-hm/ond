//! Business logic — assembles rows into the proto response.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use std::collections::HashMap;

use sqlx::PgPool;

use super::convert::{
    evidence_grade_to_proto, goal_to_proto, manner_to_proto, passage_to_proto, phase_kind_to_proto,
    reading_content_to_proto, register_to_proto, surface_to_proto,
};
use super::errors::TechniqueError;
use super::repository::{self, PhaseRow, StageRow};
use super::types::{
    FoundationHeading, Occasion, PlayablePhase, PlayableStage, ProgressionStep, Reference,
    Technique,
};
use crate::proto::ond::v1 as pb;
use crate::wire;

/// Every technique with its stages and phases, in curated presentation order.
///
/// Unpaginated and complete, because the client caches the answer and plays sessions from that
/// cache: a partial catalogue is a client that can breathe only some of the app while offline. It
/// refuses rather than trims — a catalogue short of a technique cannot be told from one without it.
pub async fn list_techniques(pool: &PgPool) -> Result<pb::ListTechniquesResponse, TechniqueError> {
    // Three sequential reads rather than a `try_join!` of them: the saving is two
    // loopback round-trips on a call each client makes once at launch, and the
    // cost is three pool connections per request instead of one.
    let techniques = repository::list_techniques(pool).await?;
    let stages = repository::list_all_stages(pool).await?;
    let phases = repository::list_all_phases(pool).await?;

    let mut stages_by_technique = assemble_playable_stages(stages, phases)?;

    let techniques = techniques
        .into_iter()
        .map(|row| {
            let stages = stages_by_technique
                .remove(&row.id)
                .ok_or_else(|| {
                    TechniqueError::Inconsistent(format!("technique `{}` has no stages", row.slug))
                })?
                .into_iter()
                .map(stage_to_proto)
                .collect::<Result<Vec<_>, TechniqueError>>()?;
            let recommended_rounds = wire::positive("recommended rounds", row.recommended_rounds)?;

            Ok(pb::Technique {
                id: row.id,
                slug: row.slug,
                name: row.name,
                summary: row.summary,
                mechanism: row.mechanism,
                mechanism_content: row
                    .mechanism_content
                    .map(|content| reading_content_to_proto(content.0)),
                evidence: row.evidence,
                evidence_content: row
                    .evidence_content
                    .map(|content| reading_content_to_proto(content.0)),
                evidence_grade: evidence_grade_to_proto(row.evidence_grade) as i32,
                goal: goal_to_proto(row.goal) as i32,
                stages,
                recommended_rounds,
                safety_note: row.safety_note,
                preparation: row.preparation,
                preparation_content: row
                    .preparation_content
                    .map(|content| reading_content_to_proto(content.0)),
                requires_subscription: row.requires_subscription,
            })
        })
        .collect::<Result<Vec<_>, TechniqueError>>()?;

    Ok(pb::ListTechniquesResponse { techniques })
}

/// The catalogue as `assistant` reads it, through [`super::cache`].
///
/// It carries the playable stages, `safety_note` and `mechanism`, and leaves `evidence` and
/// `preparation` behind — see "What the coach reads from the catalogue" in `docs/architecture.md`.
/// `pub(super)` keeps the cache the only way out, so the derivation stays a once-per-process cost.
pub(super) async fn catalogue(pool: &PgPool) -> Result<Vec<Technique>, TechniqueError> {
    // Three sequential reads, on `list_techniques`' terms and now for its
    // reason too: the concurrent fan-out this replaced was bought when the
    // catalogue was read on every assistant request, and `super::cache` reads
    // it once per process instead.
    let techniques = repository::list_techniques(pool).await?;
    let stages = repository::list_all_stages(pool).await?;
    let phases = repository::list_all_phases(pool).await?;

    let mut stages_by_technique = assemble_playable_stages(stages, phases)?;

    techniques
        .into_iter()
        .map(|row| {
            let stages = stages_by_technique.remove(&row.id).ok_or_else(|| {
                TechniqueError::Inconsistent(format!("technique `{}` has no stages", row.slug))
            })?;

            Ok(Technique {
                slug: row.slug,
                name: row.name,
                summary: row.summary,
                mechanism: row.mechanism,
                goal: row.goal,
                safety_note: row.safety_note,
                recommended_rounds: row.recommended_rounds,
                stages,
            })
        })
        .collect()
}

/// The curated reference data [`super::cache`] serves.
///
/// The occasions, the Start here progression, and the foundation headings, all three in the
/// assistant's cached prefix so the coach names the app's own entry points rather than inventing
/// advice beside them. Domain types, sequential reads and `pub(super)` for [`catalogue`]'s reasons.
pub(super) async fn reference(pool: &PgPool) -> Result<Reference, TechniqueError> {
    let occasions = repository::list_occasions(pool).await?;
    let progression = repository::list_progression_steps(pool).await?;
    let foundations = repository::list_foundation_topics(pool).await?;

    Ok(Reference {
        occasions: occasions
            .into_iter()
            .map(|row| Occasion {
                slug: row.slug,
                technique_slug: row.technique_slug,
                surface: row.surface,
                duration_ms: row.duration_ms,
                phase_durations_ms: row.phase_durations_ms,
                safety_note: row.safety_note,
            })
            .collect(),
        progression: progression
            .into_iter()
            .map(|row| ProgressionStep {
                technique_slug: row.technique_slug,
            })
            .collect(),
        foundations: foundations
            .into_iter()
            .map(|row| FoundationHeading {
                slug: row.slug,
                question: row.question,
            })
            .collect(),
    })
}

/// The breathing foundations, in curated reading order.
///
/// Served on this service rather than one of their own because they are the
/// other half of the catalogue's reference data — the same client reads them on
/// the same terms, and neither is scoped to a caller.
pub async fn list_foundations(
    pool: &PgPool,
) -> Result<pb::ListFoundationsResponse, TechniqueError> {
    let topics = repository::list_foundation_topics(pool)
        .await?
        .into_iter()
        .map(|row| pb::FoundationTopic {
            slug: row.slug,
            question: row.question,
            answer: row.answer,
            answer_content: row
                .answer_content
                .map(|content| reading_content_to_proto(content.0)),
        })
        .collect();

    Ok(pb::ListFoundationsResponse { topics })
}

/// The occasion entries and the Start here progression, both in curated order.
///
/// One call for the two: they answer one question — where somebody who has not chosen a technique
/// begins — and half of it renders half a screen. Neither gates anything, and neither reads user
/// state, so both stay on the public service. Sequential reads for [`list_techniques`]' reason.
pub async fn list_routes(pool: &PgPool) -> Result<pb::ListRoutesResponse, TechniqueError> {
    let occasions = repository::list_occasions(pool).await?;
    let progression = repository::list_progression_steps(pool).await?;

    let occasions = occasions
        .into_iter()
        .map(|row| {
            let phase_durations_ms = row
                .phase_durations_ms
                .into_iter()
                .map(|duration| {
                    wire::positive("occasion phase duration", duration)
                        .map_err(TechniqueError::from)
                })
                .collect::<Result<Vec<_>, TechniqueError>>()?;

            Ok(pb::Occasion {
                slug: row.slug,
                name: row.name,
                summary: row.summary,
                prescription: Some(pb::Prescription {
                    technique_slug: row.technique_slug,
                    goal: goal_to_proto(row.goal) as i32,
                    surface: surface_to_proto(row.surface) as i32,
                    register: register_to_proto(row.register) as i32,
                    duration_ms: wire::positive("occasion duration", row.duration_ms)?,
                    phase_durations_ms,
                    safety_note: row.safety_note,
                }),
            })
        })
        .collect::<Result<Vec<_>, TechniqueError>>()?;

    let progression = progression
        .into_iter()
        .map(|row| pb::ProgressionStep {
            technique_slug: row.technique_slug,
            note: row.note,
        })
        .collect();

    Ok(pb::ListRoutesResponse {
        occasions,
        progression,
    })
}

/// Folds the two child tables into one stage list per technique, in the domain shape.
///
/// Both inputs arrive already ordered — phases by `(technique_id, stage_ordinal, ordinal)` and
/// stages by `(technique_id, ordinal)` — so appending in iteration order preserves play order.
/// A stage with no phases is corrupt data rather than an empty stage: no client can advance past it.
fn assemble_playable_stages(
    stages: Vec<StageRow>,
    phases: Vec<PhaseRow>,
) -> Result<HashMap<String, Vec<PlayableStage>>, TechniqueError> {
    let mut phases_by_stage: HashMap<(String, i32), Vec<PlayablePhase>> = HashMap::new();
    for row in phases {
        phases_by_stage
            .entry((row.technique_id, row.stage_ordinal))
            .or_default()
            .push(PlayablePhase {
                kind: row.kind,
                passage: row.passage,
                manner: row.manner,
                duration_ms: row.duration_ms,
                min_duration_ms: row.min_duration_ms,
                max_duration_ms: row.max_duration_ms,
            });
    }

    let mut stages_by_technique: HashMap<String, Vec<PlayableStage>> = HashMap::new();
    for row in stages {
        let key = (row.technique_id, row.ordinal);
        let phases = phases_by_stage.remove(&key).ok_or_else(|| {
            TechniqueError::Inconsistent(format!(
                "stage {} of technique `{}` has no phases",
                key.1, key.0
            ))
        })?;

        stages_by_technique
            .entry(key.0)
            .or_default()
            .push(PlayableStage {
                cycles: row.cycles,
                open_ended: row.open_ended,
                phases,
            });
    }

    Ok(stages_by_technique)
}

/// One domain stage as the wire message, narrowing every count on the way —
/// the schema's `CHECK`s make a failed narrowing corrupt data, not a client's
/// fault.
fn stage_to_proto(stage: PlayableStage) -> Result<pb::Stage, TechniqueError> {
    Ok(pb::Stage {
        phases: stage
            .phases
            .into_iter()
            .map(|phase| {
                Ok(pb::Phase {
                    kind: phase_kind_to_proto(phase.kind) as i32,
                    duration_ms: wire::positive("phase duration", phase.duration_ms)?,
                    min_duration_ms: wire::positive("phase minimum", phase.min_duration_ms)?,
                    max_duration_ms: wire::positive("phase maximum", phase.max_duration_ms)?,
                    passage: passage_to_proto(phase.passage) as i32,
                    manner: manner_to_proto(phase.manner) as i32,
                })
            })
            .collect::<Result<Vec<_>, TechniqueError>>()?,
        cycles: wire::positive("stage cycles", stage.cycles)?,
        open_ended: stage.open_ended,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::technique::types::{Passage, PhaseKind};

    fn stage_row(technique_id: &str, ordinal: i32) -> StageRow {
        StageRow {
            technique_id: technique_id.to_owned(),
            ordinal,
            cycles: 1,
            open_ended: false,
        }
    }

    fn phase_row(technique_id: &str, stage_ordinal: i32, kind: PhaseKind) -> PhaseRow {
        PhaseRow {
            technique_id: technique_id.to_owned(),
            stage_ordinal,
            kind,
            passage: kind.is_breathing().then_some(Passage::Nose),
            manner: None,
            duration_ms: 4000,
            min_duration_ms: 2000,
            max_duration_ms: 8000,
        }
    }

    /// The narrowing rules are `crate::wire`'s to test; what this feature owns
    /// is that a failed narrowing surfaces as its own corrupt-data case rather
    /// than as anything a client could mistake for its fault.
    #[test]
    fn a_failed_narrowing_is_this_features_inconsistency() {
        let error: TechniqueError =
            wire::Unrepresentable("`phase duration` is `-4000`".to_owned()).into();
        assert!(matches!(error, TechniqueError::Inconsistent(_)));
    }

    /// The grouping runs through two `HashMap`s, so neither the stage order nor
    /// the phase order within a stage survives by accident. The rows here are
    /// ordered as the queries return them; what this pins is that the assembly
    /// keeps a multi-stage technique's stages in play order rather than in
    /// whichever order the map happens to iterate.
    #[test]
    fn stages_keep_their_play_order_through_the_grouping() {
        let stages = vec![stage_row("wim-hof", 0), stage_row("wim-hof", 1)];
        let phases = vec![
            phase_row("wim-hof", 0, PhaseKind::Inhale),
            phase_row("wim-hof", 0, PhaseKind::Exhale),
            phase_row("wim-hof", 1, PhaseKind::HoldOut),
        ];

        let assembled =
            assemble_playable_stages(stages, phases).expect("the fixture is consistent");
        let stages = &assembled["wim-hof"];

        assert_eq!(stages.len(), 2);
        assert_eq!(
            stages[0]
                .phases
                .iter()
                .map(|phase| phase.kind)
                .collect::<Vec<_>>(),
            vec![PhaseKind::Inhale, PhaseKind::Exhale]
        );
        assert_eq!(stages[1].phases.len(), 1);
    }

    /// A stage whose phases went missing is corrupt data, not an empty stage —
    /// the client would sit on a segment it can never advance past.
    #[test]
    fn a_phaseless_stage_is_inconsistent() {
        assert!(matches!(
            assemble_playable_stages(vec![stage_row("box-breathing", 0)], vec![]),
            Err(TechniqueError::Inconsistent(_))
        ));
    }
}
