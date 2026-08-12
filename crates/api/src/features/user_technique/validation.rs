//! The enforcement clause — a draft checked against the seeded safe ranges, or
//! the sentence saying which part of it will not do.
//!
//! This is the feature's actual domain. Everything here decides what a person is
//! allowed to store as an exercise; nothing here talks to the database or builds
//! a response.

use super::errors::UserTechniqueError;
use super::types::{
    AuthoredPhase, AuthoredStage, AuthoredTechnique, FAST_BREATHING_CYCLE_MS, MAX_CYCLES,
    MAX_NAME_CHARS, MAX_PHASES_PER_STAGE, MAX_ROUNDS, MAX_STAGES, MAX_SUMMARY_CHARS, PhaseLimits,
    TIMED_HOLD_CEILING_MS,
};
use crate::features::technique::service::{goal_from_proto, passage_from_proto};
use crate::features::technique::types::{Passage, PhaseKind};
use crate::proto::ond::v1 as pb;

/// Narrows a draft to something the domain accepts, or says which part of it it
/// will not.
///
/// The enforcement clause of the whole feature. Every duration is checked
/// against the range the *catalogue* seeds for its phase kind, so a client that
/// renders a wider dial than it should — or one that skips the dial entirely and
/// posts a number — gets the same answer. The counts below it are structural
/// rather than physiological; both live here because a client is free to offer
/// less than this and must not be trusted to offer no more.
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

/// Refuses the one composition that is dangerous rather than merely unusual:
/// fast breathing anywhere in a technique, and a hold long enough to be a target
/// somewhere in the same one.
///
/// Hyperventilation followed by a measured breath-hold is the documented way to
/// faint doing this — the carbon dioxide that would make somebody breathe has
/// been blown off, so the urge arrives after the oxygen has gone rather than
/// before. Every phase here is individually inside the catalogue's own safe
/// range and the combination still is not, which is why this cannot be a
/// per-phase check: [`PhaseLimits`] is aggregated per phase kind across every
/// closed stage in the catalogue, so it has already forgotten which technique a
/// range came from. The floors it derives are enough to compose fifty breaths a
/// minute, and the hold ceilings are enough to follow them with a target.
///
/// Whole technique rather than the stages after the fast one, for the reason
/// the seed-side rule gives: `rounds` replays the stage list, so a hold composed
/// before the fast breathing follows it on every round but the first.
///
/// The seeded catalogue is checked against the same two numbers by
/// `no_hold_after_fast_breathing_is_a_target` in `crates/migrate`. That one has
/// a second escape this has not — a seeded stage may be open-ended, so the
/// person ends the hold and there is nothing to reach — because an authored
/// stage cannot be: `user_technique_stages` has no such column, on 0012's
/// reasoning that authoring one should be unrepresentable.
fn reject_a_timed_hold_after_fast_breathing(
    stages: &[AuthoredStage],
) -> Result<(), UserTechniqueError> {
    let breathes_fast = stages.iter().any(|stage| {
        let cycle_ms: i32 = stage.phases.iter().map(|phase| phase.duration_ms).sum();
        cycle_ms < FAST_BREATHING_CYCLE_MS
    });

    if !breathes_fast {
        return Ok(());
    }

    for (position, stage) in stages.iter().enumerate() {
        for phase in &stage.phases {
            if phase.kind.is_breathing() || phase.duration_ms <= TIMED_HOLD_CEILING_MS {
                continue;
            }

            return Err(UserTechniqueError::Invalid(format!(
                "stage {} holds for {}ms, and this exercise breathes fast enough that a \
                 hold is capped at {TIMED_HOLD_CEILING_MS}ms",
                position + 1,
                phase.duration_ms
            )));
        }
    }

    Ok(())
}

/// Which of the two holds a `hold` movement stores as, given the last breath
/// before it anywhere in the draft.
///
/// A hold after an inhale is held on full lungs and one after an exhale on
/// empty; a hold with nothing before it at all is empty, because that is where a
/// session starts. This is the whole of what the composer no longer asks —
/// which of `PHASE_KIND_HOLD_IN` and `PHASE_KIND_HOLD_OUT` a hold is has never
/// been a choice, only a consequence, and asking made the picker four items long
/// so that somebody could get it wrong.
///
/// The iOS composer derives the same way, so the dial it renders is the dial
/// this server enforces. Two implementations of a one-line rule because it
/// crosses a language boundary, and this is the side that decides.
const fn hold_after(breath: Option<PhaseKind>) -> PhaseKind {
    match breath {
        Some(PhaseKind::Inhale) => PhaseKind::HoldIn,
        _ => PhaseKind::HoldOut,
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

/// What a draft phase's `movement` says, resolved into the pair the tables hold,
/// or `None` for a movement this server cannot read.
///
/// Total over the oneof, which is what makes the invariant structural rather
/// than checked: the hold arm carries no passage to drop, and neither breath arm
/// can omit one and still resolve. `None` covers an unset oneof — an older
/// client, or one that forgot — and a breath naming a passage this server does
/// not know, which are the same refusal from the author's side.
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

    /// Every phase below is individually inside the ranges the catalogue
    /// derives, and the combination is still the documented way to faint: fast
    /// breathing, then a hold long enough to be a target. The per-phase check
    /// cannot see it, because the limits it enforces have already forgotten
    /// which technique each range came from.
    ///
    /// The generous hold ceiling is the point of the fixture — this must be
    /// refused by the cross-stage rule rather than by the range check, or the
    /// test would pass without the rule existing.
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
