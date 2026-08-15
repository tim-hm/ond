//! Business logic — assembles rows into the proto response.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`.

use std::collections::HashMap;

use sqlx::PgPool;

use super::errors::TechniqueError;
use super::repository::{self, PhaseRow, StageRow};
use super::types::{
    CopyRegister, DeliverySurface, FoundationHeading, Occasion, Passage, PhaseKind, PlayablePhase,
    PlayableStage, ProgressionStep, Reference, Technique, TechniqueGoal,
};
use crate::proto::ond::v1 as pb;
use crate::wire;

/// The whole catalogue, assembled: every technique with its stages and phases,
/// in curated presentation order.
///
/// Unpaginated and complete, because the client caches the answer and plays
/// sessions from the cache — a partial catalogue would be a client that can only
/// breathe some of the app while offline.
///
/// Refuses rather than trims. A technique with no stages, a stage with no
/// phases, or a count the schema's `CHECK`s make unreachable fails the whole
/// call: a catalogue silently short of a technique is indistinguishable from one
/// that never had it.
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
                evidence: row.evidence,
                goal: goal_to_proto(row.goal) as i32,
                stages,
                recommended_rounds,
                safety_note: row.safety_note,
                requires_subscription: row.requires_subscription,
            })
        })
        .collect::<Result<Vec<_>, TechniqueError>>()?;

    Ok(pb::ListTechniquesResponse { techniques })
}

/// The catalogue as another feature reads it, through [`super::cache`].
///
/// `assistant` puts every technique in front of a model, checks every slug it
/// says back against this list, and clamps the exercise offers the model
/// proposes against each phase's safe range — so the playable stages ride
/// along with the descriptions. Routed through the service rather than letting
/// the caller take `TechniqueRow`: the row is this feature's SQL shape, and a
/// consumer holding it would make every column on `techniques` part of a
/// contract nobody wrote down.
///
/// Carries `safety_note` because the cached prompt tells the model never to
/// contradict one. The mechanisms remain client-facing catalogue copy and do
/// not enter the assistant's internal projection or prompt.
///
/// `evidence` is the exception, and stays behind on purpose. It is the one
/// piece of curated copy written specifically not to overclaim, and a model
/// handed it would paraphrase it — which is the single place a caveat reliably
/// gets softened. The coach is instructed not to promise outcomes instead, and
/// the honest paragraph reaches the person the one way it cannot be reworded:
/// verbatim, on the exercise's own screen.
///
/// It still crosses the socket, because reading it costs one column on a query
/// the catalogue needs whole and skipping it costs a second `SELECT`
/// duplicating the first. If a second unread field lands here, take the query.
///
/// `pub(super)` so [`super::cache`] is the only way out of this feature: the
/// derivation is priced as a once-per-process cost, and a caller reaching past
/// the cache would silently make it a per-request one again.
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
                goal: row.goal,
                safety_note: row.safety_note,
                recommended_rounds: row.recommended_rounds,
                stages,
            })
        })
        .collect()
}

/// The curated reference data as another feature reads it, through
/// [`super::cache`]: the occasions, the Start here progression, and the
/// foundation topics' headings.
///
/// The assistant puts all three in its cached prefix, so that the coach can name
/// the app's own entry points rather than inventing parallel advice — somebody
/// who tapped "before a presentation" and then asked the coach about it should
/// not be told something different. Routed through the service and projected
/// into domain types on the way, for [`catalogue`]'s reason: the rows are this
/// feature's SQL shape, and the answers are this feature's copy.
///
/// Sequential reads for [`list_techniques`]' reason — three loopback
/// round-trips are worth less than the two extra pool connections a `try_join!`
/// would hold. `pub(super)` for [`catalogue`]'s reason.
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
        })
        .collect();

    Ok(pb::ListFoundationsResponse { topics })
}

/// The curated routes into the catalogue: the occasion entries and the Start
/// here progression, both in curated order.
///
/// One call for the two because they answer one question — where somebody who
/// has not chosen a technique begins — and a client that had the occasions
/// without the progression would render half a screen. Neither list gates
/// anything: every route names a technique `list_techniques` already returned,
/// and this read touches no user state, which is why it stays on the public
/// service beside the catalogue.
///
/// Sequential reads for [`list_techniques`]' reason: this is a launch-time call
/// a client caches, so two loopback round-trips are worth less than the second
/// pool connection they would cost.
pub async fn list_routes(pool: &PgPool) -> Result<pb::ListRoutesResponse, TechniqueError> {
    let occasions = repository::list_occasions(pool).await?;
    let progression = repository::list_progression_steps(pool).await?;

    let occasions = occasions
        .into_iter()
        .map(|row| {
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

/// Folds the two child tables into one stage list per technique — the one
/// grouping in the file, in the domain shape. [`list_techniques`] projects
/// its result onto the wire through [`stage_to_proto`], so the invariants
/// below cannot drift between the two surfaces that read them.
///
/// Both inputs arrive already ordered — phases by `(technique_id,
/// stage_ordinal, ordinal)` and stages by `(technique_id, ordinal)` — so
/// appending in iteration order is what preserves play order through the
/// grouping. A stage with no phases is corrupt data rather than an empty
/// stage: the client would sit on a segment it can never advance past.
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
                })
            })
            .collect::<Result<Vec<_>, TechniqueError>>()?,
        cycles: wire::positive("stage cycles", stage.cycles)?,
        open_ended: stage.open_ended,
    })
}

/// Written out rather than derived, so that adding a goal to the database enum
/// without adding it to the proto fails to compile here instead of reaching a
/// client as an unmapped zero.
///
/// Shared with `features::profile`, which stores the goals someone picked at
/// onboarding: the goal vocabulary belongs to this feature, and a second copy
/// would compile happily while disagreeing.
pub(crate) const fn goal_to_proto(goal: TechniqueGoal) -> pb::TechniqueGoal {
    match goal {
        TechniqueGoal::Calm => pb::TechniqueGoal::Calm,
        TechniqueGoal::Sleep => pb::TechniqueGoal::Sleep,
        TechniqueGoal::Energy => pb::TechniqueGoal::Energy,
        TechniqueGoal::Reset => pb::TechniqueGoal::Reset,
        TechniqueGoal::Focus => pb::TechniqueGoal::Focus,
    }
}

/// The inbound direction, for the two features a client sends a goal to — the
/// profile it picked at onboarding, and the technique it authored.
///
/// `None` covers both the proto zero value and anything a newer client invents,
/// which mean the same thing here. Returned rather than reported so each caller
/// words the refusal in its own error type; what must not differ between them is
/// *which* values are goals, which is why the decision lives beside
/// [`goal_to_proto`] rather than in either caller.
pub(crate) fn goal_from_proto(raw: i32) -> Option<TechniqueGoal> {
    match pb::TechniqueGoal::try_from(raw) {
        Ok(pb::TechniqueGoal::Calm) => Some(TechniqueGoal::Calm),
        Ok(pb::TechniqueGoal::Sleep) => Some(TechniqueGoal::Sleep),
        Ok(pb::TechniqueGoal::Energy) => Some(TechniqueGoal::Energy),
        Ok(pb::TechniqueGoal::Reset) => Some(TechniqueGoal::Reset),
        Ok(pb::TechniqueGoal::Focus) => Some(TechniqueGoal::Focus),
        Ok(pb::TechniqueGoal::Unspecified) | Err(_) => None,
    }
}

/// Written out for [`goal_to_proto`]'s reason: a third surface added to the
/// database enum without being added to the proto must fail to compile here
/// rather than reach a client as an unmapped zero — and on this field the zero
/// is what a client reads to tell a real prescription from a missing one.
pub(crate) const fn surface_to_proto(surface: DeliverySurface) -> pb::DeliverySurface {
    match surface {
        DeliverySurface::FullScreen => pb::DeliverySurface::FullScreen,
        DeliverySurface::Discreet => pb::DeliverySurface::Discreet,
    }
}

/// Written out for [`goal_to_proto`]'s reason: a third register added to the
/// database enum without being added to the proto must fail to compile here
/// rather than reach a client as an unmapped zero.
const fn register_to_proto(register: CopyRegister) -> pb::CopyRegister {
    match register {
        CopyRegister::Plain => pb::CopyRegister::Plain,
        CopyRegister::Playful => pb::CopyRegister::Playful,
    }
}

pub(crate) const fn phase_kind_to_proto(kind: PhaseKind) -> pb::PhaseKind {
    match kind {
        PhaseKind::Inhale => pb::PhaseKind::Inhale,
        PhaseKind::HoldIn => pb::PhaseKind::HoldIn,
        PhaseKind::Exhale => pb::PhaseKind::Exhale,
        PhaseKind::HoldOut => pb::PhaseKind::HoldOut,
    }
}

/// Where the air goes, or `Unspecified` for a hold.
///
/// The one place the proto zero value is a legitimate answer rather than a
/// decode gap: a hold has no passage, `Phase` has no way to leave a field out,
/// and both write paths into that field are shaped so a hold cannot acquire one.
pub(crate) const fn passage_to_proto(passage: Option<Passage>) -> pb::Passage {
    match passage {
        Some(Passage::Nose) => pb::Passage::Nose,
        Some(Passage::Mouth) => pb::Passage::Mouth,
        Some(Passage::LeftNostril) => pb::Passage::LeftNostril,
        Some(Passage::RightNostril) => pb::Passage::RightNostril,
        None => pb::Passage::Unspecified,
    }
}

/// The inbound direction, on the same terms as [`goal_from_proto`]: the
/// vocabulary belongs to this feature, and `features::user_technique` is the one
/// place a client sends one.
///
/// `None` covers the proto zero value and anything a newer client invents. A
/// caller has already established that the phase is a breath — the oneof arm it
/// arrived in is what says so — so `None` here is a refusal rather than "this is
/// a hold".
pub(crate) fn passage_from_proto(raw: i32) -> Option<Passage> {
    match pb::Passage::try_from(raw) {
        Ok(pb::Passage::Nose) => Some(Passage::Nose),
        Ok(pb::Passage::Mouth) => Some(Passage::Mouth),
        Ok(pb::Passage::LeftNostril) => Some(Passage::LeftNostril),
        Ok(pb::Passage::RightNostril) => Some(Passage::RightNostril),
        Ok(pb::Passage::Unspecified) | Err(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
            duration_ms: 4000,
            min_duration_ms: 2000,
            max_duration_ms: 8000,
        }
    }

    /// The proto `_UNSPECIFIED` zero value must be unreachable from a domain
    /// value — a client that receives it cannot tell a real goal from a bug.
    #[test]
    fn no_domain_goal_maps_to_unspecified() {
        for goal in [
            TechniqueGoal::Calm,
            TechniqueGoal::Sleep,
            TechniqueGoal::Energy,
            TechniqueGoal::Reset,
            TechniqueGoal::Focus,
        ] {
            assert_ne!(goal_to_proto(goal), pb::TechniqueGoal::Unspecified);
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

    /// `Unspecified` is a real answer for a passage and a bug for everything
    /// else on the wire, so it must be reachable from `None` and from nowhere
    /// else — a client reading a nose as "the server and this app disagree"
    /// would draw the wrong exercise.
    #[test]
    fn only_a_hold_maps_to_an_unspecified_passage() {
        for passage in [
            Passage::Nose,
            Passage::Mouth,
            Passage::LeftNostril,
            Passage::RightNostril,
        ] {
            assert_ne!(passage_to_proto(Some(passage)), pb::Passage::Unspecified);
            assert_eq!(
                passage_from_proto(passage_to_proto(Some(passage)) as i32),
                Some(passage)
            );
        }

        assert_eq!(passage_to_proto(None), pb::Passage::Unspecified);
    }

    /// `DELIVERY_SURFACE_UNSPECIFIED` is how a client tells a prescription that
    /// never arrived from one that did, so no real surface may map onto it —
    /// a discreet session mistaken for a missing one is a full screen lighting
    /// up in a meeting.
    #[test]
    fn no_domain_surface_maps_to_unspecified() {
        for surface in [DeliverySurface::FullScreen, DeliverySurface::Discreet] {
            assert_ne!(
                surface_to_proto(surface),
                pb::DeliverySurface::Unspecified,
                "{surface:?}"
            );
        }
    }

    #[test]
    fn no_domain_register_maps_to_unspecified() {
        for register in [CopyRegister::Plain, CopyRegister::Playful] {
            assert_ne!(
                register_to_proto(register),
                pb::CopyRegister::Unspecified,
                "{register:?}"
            );
        }
    }

    #[test]
    fn no_domain_phase_kind_maps_to_unspecified() {
        for kind in [
            PhaseKind::Inhale,
            PhaseKind::HoldIn,
            PhaseKind::Exhale,
            PhaseKind::HoldOut,
        ] {
            assert_ne!(phase_kind_to_proto(kind), pb::PhaseKind::Unspecified);
        }
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
