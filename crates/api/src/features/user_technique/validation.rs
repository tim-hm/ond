//! A draft checked against the seeded safe ranges, or the sentence saying
//! which part of it will not do. Everything here decides what a person may
//! store as an exercise. Nothing here reads the database or builds a response.

use super::errors::UserTechniqueError;
use super::types::{
    AuthoredPhase, AuthoredStage, AuthoredTechnique, MAX_CYCLES, MAX_NAME_CHARS,
    MAX_PHASES_PER_STAGE, MAX_ROUNDS, MAX_STAGES, MAX_SUMMARY_CHARS, PhaseLimits,
};
use crate::features::technique::convert::{goal_from_proto, passage_from_proto};
use crate::features::technique::types::{Passage, PhaseKind};
use crate::proto::ond::v1 as pb;

/// Narrows a draft to something the domain accepts, or says which part it
/// refuses. Every duration is checked against the range the catalogue seeds
/// for its phase kind, so a client that renders too wide a dial gets the same
/// answer as one that posts a number directly. The counts are structural
/// rather than physiological. A client may offer less, never more.
pub(super) fn validate(
    draft: Option<pb::TechniqueDraft>,
    limits: &PhaseLimits,
) -> Result<AuthoredTechnique, UserTechniqueError> {
    let draft =
        draft.ok_or_else(|| UserTechniqueError::Invalid("`draft` is required".to_owned()))?;

    let name = draft.name.trim().to_owned();
    if name.is_empty() || width(name.chars().count()) > MAX_NAME_CHARS {
        return Err(UserTechniqueError::Invalid(format!(
            "`name` must be between 1 and {MAX_NAME_CHARS} characters"
        )));
    }

    // `profile::service::bounded_line`'s rule, and now for its reason as well as
    // its own: this name reaches the coach's prompt as a line of its own under a
    // header, so a newline inside it is a person writing the shape of a header
    // the server did not write. Nothing legitimate puts a control character in
    // the name of a breathing exercise.
    if name.chars().any(char::is_control) {
        return Err(UserTechniqueError::Invalid(
            "`name` may not contain control characters".to_owned(),
        ));
    }

    // Trimmed rather than refused for being blank: a summary nobody wrote and one
    // holding only spaces mean the same thing, and neither is an error.
    let summary = draft.summary.trim().to_owned();
    if width(summary.chars().count()) > MAX_SUMMARY_CHARS {
        return Err(UserTechniqueError::Invalid(format!(
            "`summary` must be at most {MAX_SUMMARY_CHARS} characters"
        )));
    }

    let goal = goal_from_proto(draft.goal).ok_or_else(|| {
        UserTechniqueError::Invalid(format!("`{}` is not a goal this server knows", draft.goal))
    })?;

    let rounds = bounded("rounds", draft.rounds, MAX_ROUNDS)?;

    if draft.stages.is_empty() || width(draft.stages.len()) > MAX_STAGES {
        return Err(UserTechniqueError::Invalid(format!(
            "an exercise has between 1 and {MAX_STAGES} stages"
        )));
    }

    // The breath a hold derives its lungs state from carries across stage
    // boundaries: a stage opening on a hold follows whatever the stage before it
    // ended on, exactly as the session plays it.
    let mut breath = None;
    let mut stages = Vec::with_capacity(draft.stages.len());
    for (index, stage) in draft.stages.into_iter().enumerate() {
        stages.push(validate_stage(index + 1, stage, limits, &mut breath)?);
    }

    // After the loop because it is the one rule here that spans stages, and it
    // cannot be answered until every stage is known — see the function's doc.
    reject_a_timed_hold_after_fast_breathing(&stages)?;

    Ok(AuthoredTechnique {
        name,
        summary,
        goal,
        rounds,
        stages,
    })
}

/// `position` is 1-based, because it appears in a message somebody reads beside
/// the stage they are editing.
///
/// `breath` is the last inhale or exhale seen anywhere in the draft so far, and
/// is advanced as this stage's phases are read — see [`hold_after`].
fn validate_stage(
    position: usize,
    stage: pb::DraftStage,
    limits: &PhaseLimits,
    breath: &mut Option<PhaseKind>,
) -> Result<AuthoredStage, UserTechniqueError> {
    let cycles = bounded("cycles", stage.cycles, MAX_CYCLES)?;

    if stage.phases.is_empty() || width(stage.phases.len()) > MAX_PHASES_PER_STAGE {
        return Err(UserTechniqueError::Invalid(format!(
            "stage {position} must have between 1 and {MAX_PHASES_PER_STAGE} phases"
        )));
    }

    let mut phases = Vec::with_capacity(stage.phases.len());
    for (index, phase) in stage.phases.into_iter().enumerate() {
        phases.push(validate_phase(position, index + 1, phase, limits, breath)?);
    }

    Ok(AuthoredStage { phases, cycles })
}

/// Refuses fast breathing anywhere in a technique together with a hold long
/// enough to be a target anywhere in the same one. Hyperventilation followed by
/// a measured breath-hold is the documented way to faint doing this. Each phase
/// can sit inside its own seeded [`PhaseLimits`] range and the pair still be
/// unsafe — see "Composed exercises" in `docs/architecture.md`.
fn reject_a_timed_hold_after_fast_breathing(
    stages: &[AuthoredStage],
) -> Result<(), UserTechniqueError> {
    let breathes_fast = stages.iter().any(|stage| {
        let cycle_ms: i32 = stage.phases.iter().map(|phase| phase.duration_ms).sum();
        // The whole cycle, holds included: a hold inside the repeating pattern
        // makes the rate slow, and one quick breath every forty seconds
        // accumulates carbon dioxide instead of washing it out. A stage that
        // only holds is not fast breathing at any length; without the guard it
        // would mark its whole technique fast and refuse safe holds in it.
        stage.phases.iter().any(|phase| phase.kind.is_breathing())
            && physiology::breathes_fast(cycle_ms)
    });

    if !breathes_fast {
        return Ok(());
    }

    for (position, stage) in stages.iter().enumerate() {
        for phase in &stage.phases {
            if phase.kind.is_breathing() || !physiology::is_a_timed_target(phase.duration_ms) {
                continue;
            }

            return Err(UserTechniqueError::Invalid(format!(
                "stage {} holds for {}ms, and this exercise breathes fast enough that a \
                 hold is capped at {}ms",
                position + 1,
                phase.duration_ms,
                physiology::TIMED_HOLD_CEILING_MS
            )));
        }
    }

    Ok(())
}

/// Which of the two holds a `hold` movement stores as, from the last breath
/// before it in the draft. After an inhale the lungs are full; after an exhale,
/// or with nothing before it, empty — a session starts empty. The iOS composer
/// derives it the same way, and this side decides. The match is written out so
/// a fifth air-moving `PhaseKind` cannot default to a wrong safe duration.
const fn hold_after(breath: Option<PhaseKind>) -> PhaseKind {
    match breath {
        Some(PhaseKind::Inhale) => PhaseKind::HoldIn,
        Some(PhaseKind::Exhale | PhaseKind::HoldIn | PhaseKind::HoldOut) | None => {
            PhaseKind::HoldOut
        }
    }
}

fn validate_phase(
    stage: usize,
    position: usize,
    phase: pb::DraftPhase,
    limits: &PhaseLimits,
    breath: &mut Option<PhaseKind>,
) -> Result<AuthoredPhase, UserTechniqueError> {
    let (kind, passage) = movement(phase.movement, *breath).ok_or_else(|| {
        UserTechniqueError::Invalid(format!(
            "phase {position} of stage {stage} does not say how the breath moves"
        ))
    })?;

    if kind.is_breathing() {
        *breath = Some(kind);
    }

    let limit = limits.range(kind).ok_or_else(|| {
        UserTechniqueError::Invalid(format!(
            "phase {position} of stage {stage} is of a kind with no safe range to breathe it in"
        ))
    })?;

    // Converted before comparing so that a duration past `i32::MAX` is refused
    // as a duration rather than wrapping into the range on its way to the column.
    let duration_ms = i32::try_from(phase.duration_ms).unwrap_or(i32::MAX);
    if duration_ms < limit.min_duration_ms || duration_ms > limit.max_duration_ms {
        return Err(UserTechniqueError::Invalid(format!(
            "phase {position} of stage {stage} must be between {}ms and {}ms",
            limit.min_duration_ms, limit.max_duration_ms
        )));
    }

    Ok(AuthoredPhase {
        kind,
        passage,
        duration_ms,
    })
}

/// What a draft phase's `movement` says, as the pair the tables hold, or `None`
/// for a movement this server cannot read. The match is total over the oneof,
/// so the invariant is structural: the hold arm carries no passage to drop, and
/// neither breath arm can omit one. `None` covers an unset oneof and a passage
/// this server does not know, which are one refusal to the author.
fn movement(
    movement: Option<pb::draft_phase::Movement>,
    breath: Option<PhaseKind>,
) -> Option<(PhaseKind, Option<Passage>)> {
    match movement? {
        pb::draft_phase::Movement::Inhale(raw) => {
            Some((PhaseKind::Inhale, Some(passage_from_proto(raw)?)))
        }
        pb::draft_phase::Movement::Exhale(raw) => {
            Some((PhaseKind::Exhale, Some(passage_from_proto(raw)?)))
        }
        pb::draft_phase::Movement::Hold(pb::Hold {}) => Some((hold_after(breath), None)),
    }
}

/// How many things there are, in the width the limits are stated in.
///
/// Saturating rather than wrapping: a list of more than four billion phases is
/// over every ceiling here whatever the exact number, and wrapping would put it
/// under one.
fn width(len: usize) -> u32 {
    u32::try_from(len).unwrap_or(u32::MAX)
}

/// Narrows one of the wire's unsigned counts to the closed range `1..=max`.
fn bounded(field: &str, value: u32, max: i32) -> Result<i32, UserTechniqueError> {
    let value = i32::try_from(value).unwrap_or(i32::MAX);
    if value < 1 || value > max {
        return Err(UserTechniqueError::Invalid(format!(
            "`{field}` must be between 1 and {max}"
        )));
    }

    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::user_technique::types::PhaseLimit;

    /// A stand-in for what the seed derives to, wide enough that a test can put
    /// a value clearly inside or clearly outside it.
    fn limits() -> PhaseLimits {
        PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 700,
                max_duration_ms: 12_000,
            },
        ])
    }

    fn phase(movement: pb::draft_phase::Movement, duration_ms: u32) -> pb::DraftPhase {
        pb::DraftPhase {
            duration_ms,
            movement: Some(movement),
        }
    }

    fn inhale(duration_ms: u32) -> pb::DraftPhase {
        phase(
            pb::draft_phase::Movement::Inhale(pb::Passage::Nose as i32),
            duration_ms,
        )
    }

    fn exhale(duration_ms: u32) -> pb::DraftPhase {
        phase(
            pb::draft_phase::Movement::Exhale(pb::Passage::Nose as i32),
            duration_ms,
        )
    }

    fn hold(duration_ms: u32) -> pb::DraftPhase {
        phase(pb::draft_phase::Movement::Hold(pb::Hold {}), duration_ms)
    }

    fn draft(phases: Vec<pb::DraftPhase>) -> pb::TechniqueDraft {
        pb::TechniqueDraft {
            name: "Mine".to_owned(),
            summary: String::new(),
            goal: pb::TechniqueGoal::Calm as i32,
            stages: vec![pb::DraftStage { phases, cycles: 8 }],
            rounds: 1,
        }
    }

    #[test]
    fn a_draft_inside_the_seeded_ranges_is_accepted() {
        let authored = validate(Some(draft(vec![inhale(4000), exhale(6000)])), &limits())
            .expect("4s in and 6s out sit inside the seeded ranges");

        assert_eq!(authored.stages.len(), 1);
        assert_eq!(authored.stages[0].cycles, 8);
        assert_eq!(
            authored.stages[0]
                .phases
                .iter()
                .map(|phase| (phase.kind, phase.passage, phase.duration_ms))
                .collect::<Vec<_>>(),
            vec![
                (PhaseKind::Inhale, Some(Passage::Nose), 4000),
                (PhaseKind::Exhale, Some(Passage::Nose), 6000),
            ]
        );
    }

    /// Every phase below is inside the ranges the catalogue derives, and the
    /// combination is still the documented way to faint. The generous hold
    /// ceiling is the point of the fixture: the cross-stage rule must refuse
    /// this draft, not the range check, or the test would pass without the
    /// rule existing.
    #[test]
    fn fast_breathing_may_not_be_followed_by_a_hold_worth_beating() {
        let limits = PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 700,
                max_duration_ms: 12_000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldOut,
                min_duration_ms: 500,
                max_duration_ms: 45_000,
            },
        ]);

        // A one-second cycle — sixty breaths a minute — and then forty seconds
        // of holding it.
        let mut draft = draft(vec![inhale(500), exhale(700)]);
        draft.stages.push(pb::DraftStage {
            phases: vec![hold(40_000)],
            cycles: 1,
        });

        // Matched on the message as well as the variant: every refusal in this
        // file is `Invalid`, so the variant alone would pass on a draft turned
        // away for its name.
        assert!(
            matches!(
                validate(Some(draft), &limits),
                Err(UserTechniqueError::Invalid(said)) if said.contains("breathes fast")
            ),
            "fast breathing followed by a 40s hold is the blackout pattern"
        );
    }

    /// The same hold, composed without the fast breathing in front of it, is an
    /// ordinary long hold and stays allowed. The rule is about the combination
    /// — a ceiling on every hold would refuse the breath-hold practice this
    /// catalogue is built to teach.
    #[test]
    fn a_long_hold_after_slow_breathing_is_still_allowed() {
        let limits = PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 700,
                max_duration_ms: 12_000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldOut,
                min_duration_ms: 500,
                max_duration_ms: 45_000,
            },
        ]);

        let mut draft = draft(vec![inhale(5000), exhale(6000)]);
        draft.stages.push(pb::DraftStage {
            phases: vec![hold(40_000)],
            cycles: 1,
        });

        assert!(
            validate(Some(draft), &limits).is_ok(),
            "an eleven-second cycle is not over-breathing"
        );
    }

    /// A stage that only holds is short, and shortness is what the fast rule
    /// measures — so without a guard for "did any air move", a brief hold stage
    /// marks its whole technique as over-breathing and starts refusing the
    /// perfectly safe holds elsewhere in it.
    #[test]
    fn a_stage_that_only_holds_is_not_fast_breathing() {
        let limits = PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 700,
                max_duration_ms: 12_000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldOut,
                min_duration_ms: 500,
                max_duration_ms: 45_000,
            },
        ]);

        // Slow breathing throughout, and a two-second hold stage whose total is
        // well under the fast-breathing cycle.
        let mut draft = draft(vec![inhale(5000), exhale(6000)]);
        draft.stages.push(pb::DraftStage {
            phases: vec![hold(2_000)],
            cycles: 1,
        });
        draft.stages.push(pb::DraftStage {
            phases: vec![hold(40_000)],
            cycles: 1,
        });

        assert!(
            validate(Some(draft), &limits).is_ok(),
            "a short hold is not a fast breath, and must not make one out of its technique"
        );
    }

    /// The whole of what the composer stopped asking. A hold is one choice to
    /// the person authoring it; which of the two it stores as is a consequence
    /// of the breath before it, and that includes the breath in the stage
    /// before it.
    #[test]
    fn a_hold_takes_its_lungs_state_from_the_breath_before_it() {
        let limits = PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 700,
                max_duration_ms: 12_000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldIn,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldOut,
                min_duration_ms: 500,
                max_duration_ms: 10_000,
            },
        ]);

        let mut boxed = draft(vec![
            hold(4000),
            inhale(4000),
            hold(4000),
            exhale(4000),
            hold(4000),
        ]);
        boxed.stages.push(pb::DraftStage {
            phases: vec![hold(4000)],
            cycles: 1,
        });

        let authored = validate(Some(boxed), &limits).expect("every phase is inside its range");

        assert_eq!(
            authored.stages[0]
                .phases
                .iter()
                .map(|phase| phase.kind)
                .collect::<Vec<_>>(),
            vec![
                // Nothing before it: a session starts on empty lungs.
                PhaseKind::HoldOut,
                PhaseKind::Inhale,
                PhaseKind::HoldIn,
                PhaseKind::Exhale,
                PhaseKind::HoldOut,
            ]
        );
        assert_eq!(authored.stages[1].phases[0].kind, PhaseKind::HoldOut);
        assert!(
            authored.stages[0]
                .phases
                .iter()
                .filter(|phase| !phase.kind.is_breathing())
                .all(|phase| phase.passage.is_none())
        );
    }

    /// The refusals the oneof leaves for the server: a phase that names no
    /// movement at all, and a breath that names a passage this server does not
    /// know. Neither is a shape a current client can build — which is the point
    /// of checking they are refused rather than defaulted.
    #[test]
    fn a_phase_with_no_movement_or_no_passage_is_refused() {
        let nothing = pb::DraftPhase {
            duration_ms: 4000,
            movement: None,
        };
        let nowhere = phase(
            pb::draft_phase::Movement::Inhale(pb::Passage::Unspecified as i32),
            4000,
        );

        for phase in [nothing, nowhere] {
            assert!(matches!(
                validate(Some(draft(vec![phase])), &limits()),
                Err(UserTechniqueError::Invalid(_))
            ));
        }
    }

    /// The clause the whole feature exists to hold. A client is free to render
    /// whatever dial it likes; what it cannot do is store a breath the seeded
    /// evidence does not support.
    #[test]
    fn a_phase_outside_its_seeded_range_is_refused_at_either_end() {
        for duration in [400, 10_001] {
            assert!(
                matches!(
                    validate(Some(draft(vec![inhale(duration)])), &limits()),
                    Err(UserTechniqueError::Invalid(_))
                ),
                "{duration}ms is outside the seeded inhale range and must be refused"
            );
        }
    }

    /// A kind the catalogue never uses in a closed stage has no evidence behind
    /// any duration, so it is refused rather than given an invented range —
    /// which is the difference between enforcing a limit and inventing one.
    #[test]
    fn a_phase_kind_with_no_seeded_range_is_refused() {
        assert!(matches!(
            validate(Some(draft(vec![hold(4000)])), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));
    }

    /// `duration_ms` is unsigned on the wire and signed in the column, so the
    /// conversion is the one place a huge value could wrap into the accepted
    /// range instead of being refused.
    #[test]
    fn an_unrepresentable_duration_is_refused_rather_than_wrapped() {
        assert!(matches!(
            validate(Some(draft(vec![inhale(u32::MAX)])), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));
    }

    #[test]
    fn the_structural_counts_are_bounded_at_both_ends() {
        let mut no_phases = draft(vec![]);
        no_phases.stages[0].cycles = 8;
        assert!(matches!(
            validate(Some(no_phases), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));

        let mut no_cycles = draft(vec![inhale(4000)]);
        no_cycles.stages[0].cycles = 0;
        assert!(matches!(
            validate(Some(no_cycles), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));

        let mut too_many_rounds = draft(vec![inhale(4000)]);
        too_many_rounds.rounds = MAX_ROUNDS.unsigned_abs() + 1;
        assert!(matches!(
            validate(Some(too_many_rounds), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));

        let mut too_many_stages = draft(vec![inhale(4000)]);
        too_many_stages.stages =
            std::iter::repeat_n(too_many_stages.stages[0].clone(), MAX_STAGES as usize + 1)
                .collect();
        assert!(matches!(
            validate(Some(too_many_stages), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));
    }

    /// A summary nobody wrote and one holding only spaces are the same thing,
    /// and the schema's `CHECK` is a backstop rather than the guard — so an
    /// over-long one has to come back naming the field.
    #[test]
    fn a_summary_is_optional_but_bounded() {
        let absent = validate(Some(draft(vec![inhale(4000)])), &limits())
            .expect("a draft with no summary is an ordinary draft");
        assert!(absent.summary.is_empty());

        let mut blank = draft(vec![inhale(4000)]);
        blank.summary = "  \n ".to_owned();
        assert!(
            validate(Some(blank), &limits())
                .expect("whitespace is nothing written, not a refusal")
                .summary
                .is_empty()
        );

        let mut written = draft(vec![inhale(4000)]);
        written.summary = "  For the ten minutes before a difficult call.  ".to_owned();
        assert_eq!(
            validate(Some(written), &limits())
                .expect("a sentence is inside the bound")
                .summary,
            "For the ten minutes before a difficult call."
        );

        let mut essay = draft(vec![inhale(4000)]);
        essay.summary = "e".repeat(MAX_SUMMARY_CHARS as usize + 1);
        assert!(matches!(
            validate(Some(essay), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));
    }

    #[test]
    fn a_nameless_draft_is_refused() {
        let mut nameless = draft(vec![inhale(4000)]);
        nameless.name = "   ".to_owned();

        assert!(matches!(
            validate(Some(nameless), &limits()),
            Err(UserTechniqueError::Invalid(_))
        ));
    }
}
