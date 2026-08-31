//! Stored rows and validated drafts, as the same `Technique` message the
//! catalogue serves.
//!
//! Domain-to-wire only, so a client plays a personal and a curated exercise
//! through one path. The inbound direction is `super::validation`.

use std::collections::HashMap;

use uuid::Uuid;

use super::errors::UserTechniqueError;
use super::repository::{PhaseRow, StageRow};
use super::types::{
    AuthoredTechnique, MAX_CYCLES, MAX_NAME_CHARS, MAX_PHASES_PER_STAGE, MAX_ROUNDS, MAX_STAGES,
    MAX_SUMMARY_CHARS, MAX_TECHNIQUES, PhaseLimits,
};
use crate::features::technique::convert::{
    evidence_grade_to_proto, goal_to_proto, phase_kind_to_proto, phase_to_proto,
};
use crate::features::technique::types::{Passage, PhaseKind, PlayablePhase, TechniqueGoal};
use crate::proto::ond::v1 as pb;
use crate::wire;

/// The slug a personal technique travels under, in `sessions.technique_slug`
/// above all. Prefixed so a slug that resolves to nothing in the catalogue
/// reads as a personal technique, not a corrupt curated one. A `String` and
/// not a `TechniqueSlug` because it is minted here rather than narrowed from a
/// client; the test below pins the bound the constructor would apply.
fn slug_for(id: Uuid) -> String {
    format!("own-{id}")
}

/// The technique a write just stored, without reading it back. The validated
/// draft is exactly what went into the tables, so a round-trip would spend
/// three queries confirming what this process just wrote. The narrowing below
/// runs here too, though no value can be negative: these converters serve
/// reads and writes alike, with no exception.
pub(super) fn authored_to_proto(
    id: Uuid,
    authored: &AuthoredTechnique,
    limits: &PhaseLimits,
) -> Result<pb::Technique, UserTechniqueError> {
    let stages = authored
        .stages
        .iter()
        .map(|stage| {
            Ok(pb::Stage {
                phases: stage
                    .phases
                    .iter()
                    .map(|phase| {
                        authored_phase_to_proto(
                            phase.kind,
                            phase.passage,
                            phase.duration_ms,
                            limits,
                        )
                    })
                    .collect::<Result<Vec<_>, UserTechniqueError>>()?,
                cycles: wire::positive("stage cycles", stage.cycles)?,
                open_ended: false,
            })
        })
        .collect::<Result<Vec<_>, UserTechniqueError>>()?;

    technique_to_proto(
        StoredTechnique {
            id,
            name: &authored.name,
            summary: &authored.summary,
            goal: authored.goal,
            rounds: authored.rounds,
        },
        stages,
    )
}

/// A technique's own columns, apart from the stages it plays.
///
/// A struct rather than five arguments because `name` and `summary` are
/// adjacent `&str`s. The compiler cannot catch a transposition, and the two
/// read very differently on the screen they arrive at.
#[derive(Clone, Copy)]
pub(super) struct StoredTechnique<'a> {
    pub(super) id: Uuid,
    pub(super) name: &'a str,
    pub(super) summary: &'a str,
    pub(super) goal: TechniqueGoal,
    pub(super) rounds: i32,
}

/// The one place a stored technique becomes the message the catalogue also
/// speaks, so a client plays a personal and a curated one through one path.
///
/// `summary` is the author's own, carried in the field the catalogue's curated
/// sentence arrives in, so no surface needs a second branch.
pub(super) fn technique_to_proto(
    technique: StoredTechnique<'_>,
    stages: Vec<pb::Stage>,
) -> Result<pb::Technique, UserTechniqueError> {
    Ok(pb::Technique {
        id: technique.id.to_string(),
        slug: slug_for(technique.id),
        name: technique.name.to_owned(),
        summary: technique.summary.to_owned(),
        // Curated copy nobody may write on an author's behalf: a mechanism, a
        // literature, or an evidence grade for a pattern somebody invented
        // this morning. `requires_subscription` is false because what is
        // served back is the author's own work.
        mechanism: String::new(),
        mechanism_content: None,
        evidence: String::new(),
        evidence_content: None,
        evidence_grade: evidence_grade_to_proto(None) as i32,
        goal: goal_to_proto(technique.goal) as i32,
        stages,
        recommended_rounds: wire::positive("recommended rounds", technique.rounds)?,
        // Empty: this feature refuses to leave the ranges it would caution about.
        safety_note: String::new(),
        // Curated copy too — what to do with your body before the first breath.
        preparation: String::new(),
        preparation_content: None,
        requires_subscription: false,
    })
}

/// Stamps the seeded range onto a stored phase, widened to hold the stored
/// duration where the two disagree. They disagree only when the catalogue
/// narrowed after the technique was authored. Refusing would cost the person
/// their whole list, and clamping would change their exercise silently. The
/// next edit is checked against the current range.
fn authored_phase_to_proto(
    kind: PhaseKind,
    passage: Option<Passage>,
    duration_ms: i32,
    limits: &PhaseLimits,
) -> Result<pb::Phase, UserTechniqueError> {
    let (min, max) = limits
        .range(kind)
        .map_or((duration_ms, duration_ms), |limit| {
            (limit.min_duration_ms, limit.max_duration_ms)
        });

    phase_to_proto(PlayablePhase {
        kind,
        passage,
        duration_ms,
        min_duration_ms: min.min(duration_ms),
        max_duration_ms: max.max(duration_ms),
        // An authored exercise names neither a manner nor a cadence. Both are
        // curated copy: a manner asserts how a shaped breath works, and the gap
        // between two breaths, the tap and the spoken line are one authored
        // deliverable per exercise. The composer invites neither. Absent leaves
        // the client deriving them, which is what it does for the catalogue too.
        manner: None,
        turn_gap_ms: None,
        haptic_pattern: None,
        voice_script: None,
    })
    .map_err(Into::into)
}

/// The composer's ceilings, as the client has to render them.
///
/// The two duration bounds are the seeded catalogue's own columns and narrow
/// like any other stored value; the counts beside them are `MAX_*` constants
/// this binary was compiled with, which is why they cannot fail.
pub(super) fn limits_to_proto(
    limits: &PhaseLimits,
) -> Result<pb::AuthoringLimits, UserTechniqueError> {
    Ok(pb::AuthoringLimits {
        phases: limits
            .iter()
            .map(|limit| {
                Ok(pb::PhaseLimit {
                    kind: phase_kind_to_proto(limit.kind) as i32,
                    min_duration_ms: wire::positive("phase minimum", limit.min_duration_ms)?,
                    max_duration_ms: wire::positive("phase maximum", limit.max_duration_ms)?,
                })
            })
            .collect::<Result<Vec<_>, UserTechniqueError>>()?,
        max_name_chars: MAX_NAME_CHARS,
        max_summary_chars: MAX_SUMMARY_CHARS,
        max_stages: MAX_STAGES,
        max_phases_per_stage: MAX_PHASES_PER_STAGE,
        max_cycles: MAX_CYCLES.unsigned_abs(),
        max_rounds: MAX_ROUNDS.unsigned_abs(),
        max_techniques: MAX_TECHNIQUES,
    })
}

/// Folds the two child tables into one stage list per technique.
///
/// Both arrive ordered by `(technique_id, ordinal)`, so appending in iteration
/// order preserves play order. Not shared with the catalogue's assembly: that
/// one keys on a text id and carries `open_ended` and a per-row range.
pub(super) fn assemble_stages(
    stages: Vec<StageRow>,
    phases: Vec<PhaseRow>,
    limits: &PhaseLimits,
) -> Result<HashMap<Uuid, Vec<pb::Stage>>, UserTechniqueError> {
    let mut phases_by_stage: HashMap<(Uuid, i32), Vec<pb::Phase>> = HashMap::new();
    for phase in phases {
        phases_by_stage
            .entry((phase.technique_id, phase.stage_ordinal))
            .or_default()
            .push(authored_phase_to_proto(
                phase.kind,
                phase.passage,
                phase.duration_ms,
                limits,
            )?);
    }

    let mut stages_by_technique: HashMap<Uuid, Vec<pb::Stage>> = HashMap::new();
    for stage in stages {
        let key = (stage.technique_id, stage.ordinal);
        let phases = phases_by_stage.remove(&key).ok_or_else(|| {
            UserTechniqueError::Inconsistent(format!(
                "stage {} of technique `{}` has no phases",
                key.1, key.0
            ))
        })?;

        stages_by_technique
            .entry(key.0)
            .or_default()
            .push(pb::Stage {
                phases,
                cycles: wire::positive("stage cycles", stage.cycles)?,
                open_ended: false,
            });
    }

    Ok(stages_by_technique)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::technique::types::MAX_SLUG_CHARS;
    use crate::features::user_technique::types::PhaseLimit;

    /// A stand-in for what the seed derives to, wide enough that a test can put
    /// a value clearly inside or clearly outside it.
    fn limits() -> PhaseLimits {
        PhaseLimits::new(vec![PhaseLimit {
            kind: PhaseKind::Inhale,
            min_duration_ms: 500,
            max_duration_ms: 10_000,
        }])
    }

    /// The client rejects a phase whose duration sits outside its own range, so
    /// a seed that narrowed under a stored technique would cost somebody their
    /// whole list. The range widens to contain what they authored instead.
    #[test]
    fn a_stored_phase_narrower_than_its_range_still_serves() {
        let phase =
            authored_phase_to_proto(PhaseKind::Inhale, Some(Passage::Nose), 12_000, &limits())
                .expect("a duration outside the seeded range is widened, not refused");

        assert_eq!(phase.duration_ms, 12_000);
        assert!(phase.min_duration_ms <= phase.duration_ms);
        assert!(phase.duration_ms <= phase.max_duration_ms);
    }

    /// The columns all carry `CHECK (… > 0)`, so a value outside that is
    /// corrupt rather than authored. `unsigned_abs` would serve `4000` for a
    /// stored `-4000`, which a client cannot tell from a real phase. Zero fails
    /// too: the client refuses a zero-length phase, so the server naming the
    /// row is the more useful refusal.
    #[test]
    fn a_corrupt_stored_duration_fails_the_call_rather_than_flipping_sign() {
        for duration in [-4000, 0] {
            assert!(
                matches!(
                    authored_phase_to_proto(
                        PhaseKind::Inhale,
                        Some(Passage::Nose),
                        duration,
                        &limits()
                    ),
                    Err(UserTechniqueError::Inconsistent(_))
                ),
                "a stored {duration}ms phase is corrupt and must fail the call"
            );
        }

        assert!(matches!(
            technique_to_proto(
                StoredTechnique {
                    id: Uuid::nil(),
                    name: "Mine",
                    summary: "",
                    goal: TechniqueGoal::Calm,
                    rounds: -3,
                },
                vec![],
            ),
            Err(UserTechniqueError::Inconsistent(_))
        ));
    }

    /// A slug that resolves to nothing in the catalogue reaches the journey's
    /// history and the assistant's prompt, and both have to be able to tell a
    /// personal exercise from a corrupted curated one.
    #[test]
    fn a_personal_slug_is_recognisable_and_fits_the_session_column() {
        let slug = slug_for(Uuid::nil());

        assert!(slug.starts_with("own-"));
        assert!(slug.chars().count() <= MAX_SLUG_CHARS);
    }
}
