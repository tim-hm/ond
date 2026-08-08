//! Stored rows and validated drafts, as the same `Technique` message the
//! catalogue serves.
//!
//! One direction only — everything here goes domain-to-wire, which is what lets
//! a client play a personal exercise and a curated one through a single path.
//! The inbound direction is `super::validation`.

use std::collections::HashMap;

use uuid::Uuid;

use super::errors::UserTechniqueError;
use super::repository::{PhaseRow, StageRow};
use super::types::{
    AuthoredTechnique, MAX_CYCLES, MAX_NAME_CHARS, MAX_PHASES_PER_STAGE, MAX_ROUNDS, MAX_STAGES,
    MAX_SUMMARY_CHARS, MAX_TECHNIQUES, PhaseLimits,
};
use crate::features::technique::service::{goal_to_proto, passage_to_proto, phase_kind_to_proto};
use crate::features::technique::types::{Passage, PhaseKind, TechniqueGoal};
use crate::proto::ond::v1 as pb;

/// The stable key a technique somebody built is known by everywhere a catalogue
/// technique is known by its slug — `sessions.technique_slug` above all.
///
/// Prefixed rather than bare, so a slug that resolves to nothing in the
/// catalogue is legible as a personal technique rather than as a corrupted
/// curated one, in a history row or a log line. Nothing parses the prefix back
/// out: the id is the identity, and this is the name it travels under.
fn slug_for(id: Uuid) -> String {
    format!("own-{id}")
}

/// Narrows a stored count back to the width the wire states it in, on the terms
/// `technique::service::positive_count` states for the catalogue's own columns:
/// `0012_user_techniques.sql` constrains every one of these to be `> 0`, so a
/// value outside that is corrupt data rather than a number anybody authored, and
/// `unsigned_abs` would serve `-4000` back as a plausible `4000`.
///
/// Zero fails here where the catalogue's twin lets it through, because the
/// client refuses it either way: a zero duration comes back as a whole personal
/// list this app cannot read, and naming the row is the more useful of the two
/// refusals.
///
/// Applied on the write paths too, where the value was validated in-memory this
/// request and provably cannot be negative — the converters here serve reads
/// and writes alike, so a rule with an exception would be a rule the next caller
/// has to place itself against. The `MAX_*` ceilings stay on `unsigned_abs`:
/// they are compile-time constants rather than anything a row can carry.
fn positive_count(field: &str, value: i32) -> Result<u32, UserTechniqueError> {
    u32::try_from(value)
        .ok()
        .filter(|count| *count > 0)
        .ok_or_else(|| {
            UserTechniqueError::Inconsistent(format!("{field} `{value}` is not a positive count"))
        })
}

/// The technique a write just stored, without reading it back.
///
/// The validated draft is already exactly what went into the tables, so a
/// round-trip would spend three queries confirming what this process just wrote.
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
                        phase_to_proto(phase.kind, phase.passage, phase.duration_ms, limits)
                    })
                    .collect::<Result<Vec<_>, UserTechniqueError>>()?,
                cycles: positive_count("stage cycles", stage.cycles)?,
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

/// What a technique is, apart from the stages it plays — the row's own columns,
/// in the widths they are stored in.
///
/// A struct rather than five arguments because `name` and `summary` are adjacent
/// `&str`s that transpose without a word from the compiler, and the two say very
/// different things on the screen they arrive at. Same discipline `UserId`
/// establishes, at the one signature on this feature where a swap was free.
#[derive(Clone, Copy)]
pub(super) struct StoredTechnique<'a> {
    pub(super) id: Uuid,
    pub(super) name: &'a str,
    pub(super) summary: &'a str,
    pub(super) goal: TechniqueGoal,
    pub(super) rounds: i32,
}

/// The one place a stored technique becomes the message the catalogue also
/// speaks, which is what lets a client play both through one path.
///
/// `summary` is the author's own, carried in the field the catalogue's curated
/// sentence arrives in so that every surface reading one reads the other with no
/// second branch. Empty where they wrote nothing, which is the same empty a
/// screen already handles.
///
/// Two fields are empty by construction rather than by omission: no
/// `safety_note`, because the ranges it would caution about are the ones this
/// feature refuses to leave, and `requires_subscription` is false, because what
/// is being served back is their own work.
pub(super) fn technique_to_proto(
    technique: StoredTechnique<'_>,
    stages: Vec<pb::Stage>,
) -> Result<pb::Technique, UserTechniqueError> {
    Ok(pb::Technique {
        id: technique.id.to_string(),
        slug: slug_for(technique.id),
        name: technique.name.to_owned(),
        summary: technique.summary.to_owned(),
        goal: goal_to_proto(technique.goal) as i32,
        stages,
        recommended_rounds: positive_count("recommended rounds", technique.rounds)?,
        safety_note: String::new(),
        requires_subscription: false,
    })
}

/// Stamps the seeded range onto a stored phase.
///
/// Widened to contain the stored duration where the two disagree. They can only
/// disagree by the catalogue's ranges having narrowed since the technique was
/// authored, and the alternative readings are both worse: refusing the phase
/// costs the person their whole list over a seed edit, and clamping it changes
/// what their exercise does without telling them. Widening here keeps it
/// playing as authored, and the next edit is validated against the current
/// range like any other.
fn phase_to_proto(
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

    Ok(pb::Phase {
        kind: phase_kind_to_proto(kind) as i32,
        duration_ms: positive_count("phase duration", duration_ms)?,
        min_duration_ms: positive_count("phase minimum", min.min(duration_ms))?,
        max_duration_ms: positive_count("phase maximum", max.max(duration_ms))?,
        passage: passage_to_proto(passage) as i32,
    })
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
                    min_duration_ms: positive_count("phase minimum", limit.min_duration_ms)?,
                    max_duration_ms: positive_count("phase maximum", limit.max_duration_ms)?,
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
/// order is what preserves play order through the grouping. Deliberately not
/// shared with the catalogue's own assembly, close as the two look: that one
/// keys on a text id and carries `open_ended` and a per-row range this feature
/// has neither of, and unifying them would mean one function taking three
/// arguments to say which half of itself to run.
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
            .push(phase_to_proto(
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
                cycles: positive_count("stage cycles", stage.cycles)?,
                open_ended: false,
            });
    }

    Ok(stages_by_technique)
}

#[cfg(test)]
mod tests {
    use super::*;
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
        let phase = phase_to_proto(PhaseKind::Inhale, Some(Passage::Nose), 12_000, &limits())
            .expect("a duration outside the seeded range is widened, not refused");

        assert_eq!(phase.duration_ms, 12_000);
        assert!(phase.min_duration_ms <= phase.duration_ms);
        assert!(phase.duration_ms <= phase.max_duration_ms);
    }

    /// The columns all carry `CHECK (… > 0)`, so anything outside that is
    /// corrupt data rather than a value somebody authored — and serving it
    /// through `unsigned_abs` would hand a client `4000` for a stored `-4000`,
    /// which is indistinguishable from a phase they wrote. Zero fails on the
    /// same terms: the client refuses a zero-length phase, so the server naming
    /// the row is the more useful of the two refusals.
    #[test]
    fn a_corrupt_stored_duration_fails_the_call_rather_than_flipping_sign() {
        for duration in [-4000, 0] {
            assert!(
                matches!(
                    phase_to_proto(PhaseKind::Inhale, Some(Passage::Nose), duration, &limits()),
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
        assert!(slug.chars().count() <= 64);
    }
}
