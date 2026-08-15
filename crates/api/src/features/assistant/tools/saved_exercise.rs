use serde::Deserialize;

use super::super::model::ToolSpec;
use super::{clamped, clamped_ms};
use crate::features::technique::service::{goal_to_proto, passage_to_proto};
use crate::features::technique::types::{Passage, TechniqueGoal};
use crate::features::user_technique::service as user_technique;
use crate::features::user_technique::types::{MAX_CYCLES, MAX_ROUNDS, PhaseLimits};
use crate::proto::ond::v1 as pb;

/// The model-facing name used by both the schema and dispatcher.
pub(super) const NAME: &str = "offer_saved_exercise";

/// The `offer_saved_exercise` tool as Chat declares it.
///
/// Its goal, movement, and passage enums mirror deployment-stable database and
/// wire vocabulary. Unlike catalogue slugs, inlining them cannot make the
/// provider's cached tool bytes vary with seeded content.
pub(super) fn spec() -> ToolSpec {
    ToolSpec {
        name: NAME,
        description: "Offer to save a breathing pattern as one of the person's own \
             exercises. Call it at most once, after your prose, and only where the \
             conversation has settled on a pattern worth keeping rather than one \
             worth doing now — a pattern you adjusted for them, or one they \
             described. Name it in their terms, not the catalogue's.",
        input_schema: serde_json::json!({
            "type": "object",
            "required": ["name", "goal", "stages"],
            "additionalProperties": false,
            "properties": {
                "name": {
                    "type": "string",
                    "description": "A short name, in the person's own terms."
                },
                "summary": {
                    "type": "string",
                    "description": "One sentence on what they reach for it for. Omit where the name says it."
                },
                "goal": {
                    "type": "string",
                    "enum": ["calm", "sleep", "energy", "reset", "focus"],
                    "description": "What they reach for it for, which is how it is grouped and coloured."
                },
                "rounds": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 10,
                    "description": "How many times the whole stage list repeats. Omit for one."
                },
                "stages": {
                    "type": "array",
                    "description": "The session, in play order. At least one.",
                    "items": {
                        "type": "object",
                        "required": ["phases"],
                        "additionalProperties": false,
                        "properties": {
                            "cycles": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 99,
                                "description": "How many times this stage's phases repeat. Omit for one."
                            },
                            "phases": {
                                "type": "array",
                                "description": "One breath's worth of phases, in order.",
                                "items": {
                                    "type": "object",
                                    "required": ["kind", "seconds"],
                                    "additionalProperties": false,
                                    "properties": {
                                        "kind": {
                                            "type": "string",
                                            "enum": ["inhale", "exhale", "hold"],
                                            "description": "A hold is just `hold` — whether it counts as held-in or held-out follows from the phase before it."
                                        },
                                        "passage": {
                                            "type": "string",
                                            "enum": ["nose", "mouth", "left_nostril", "right_nostril"],
                                            "description": "Where the air goes. Required on an inhale or exhale, omitted on a hold."
                                        },
                                        "seconds": {
                                            "type": "number",
                                            "description": "How long this phase lasts, inside the ranges the catalogue's patterns show."
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedExerciseInput {
    name: String,
    #[serde(default)]
    summary: String,
    goal: TechniqueGoal,
    #[serde(default)]
    rounds: Option<i64>,
    stages: Vec<SavedStageInput>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedStageInput {
    #[serde(default)]
    cycles: Option<i64>,
    phases: Vec<SavedPhaseInput>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedPhaseInput {
    kind: SavedPhaseKind,
    #[serde(default)]
    passage: Option<Passage>,
    seconds: f64,
}

/// The three movements the saved-exercise schema declares.
///
/// Holds do not encode full versus empty; the authored-technique validator
/// derives that from phase order, while a fabricated movement fails decoding.
#[derive(Deserialize, Clone, Copy)]
#[serde(rename_all = "snake_case")]
enum SavedPhaseKind {
    Inhale,
    Exhale,
    Hold,
}

/// The saved-exercise payload this input supports.
///
/// This module first shapes the model's vocabulary, then asks the owning
/// user-technique feature to validate the complete draft against current phase
/// limits. A card therefore cannot propose something the create RPC refuses.
pub(super) fn payload(
    input_json: &str,
    limits: &PhaseLimits,
) -> Option<pb::chat_response::Payload> {
    let draft = draft(input_json)?;
    user_technique::validate_draft(draft.clone(), limits).ok()?;
    Some(pb::chat_response::Payload::SavedExercise(draft))
}

fn draft(input_json: &str) -> Option<pb::TechniqueDraft> {
    let input: SavedExerciseInput = serde_json::from_str(input_json).ok()?;
    let stages = input
        .stages
        .iter()
        .map(|stage| {
            let phases = stage
                .phases
                .iter()
                .map(|phase| {
                    let air = passage_to_proto(Some(phase.passage.unwrap_or(Passage::Nose))) as i32;
                    let movement = match phase.kind {
                        SavedPhaseKind::Inhale => pb::draft_phase::Movement::Inhale(air),
                        SavedPhaseKind::Exhale => pb::draft_phase::Movement::Exhale(air),
                        SavedPhaseKind::Hold => pb::draft_phase::Movement::Hold(pb::Hold {}),
                    };
                    pb::DraftPhase {
                        movement: Some(movement),
                        duration_ms: clamped_ms(phase.seconds, 0, i32::MAX).unsigned_abs(),
                    }
                })
                .collect();

            Some(pb::DraftStage {
                phases,
                cycles: clamped(stage.cycles.unwrap_or(1), MAX_CYCLES)?,
            })
        })
        .collect::<Option<Vec<_>>>()?;

    Some(pb::TechniqueDraft {
        name: input.name,
        summary: input.summary,
        goal: goal_to_proto(input.goal) as i32,
        stages,
        rounds: clamped(input.rounds.unwrap_or(1), MAX_ROUNDS)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::technique::types::PhaseKind;
    use crate::features::user_technique::types::PhaseLimit;

    fn limits() -> PhaseLimits {
        PhaseLimits::new(vec![
            PhaseLimit {
                kind: PhaseKind::Inhale,
                min_duration_ms: 2000,
                max_duration_ms: 8000,
            },
            PhaseLimit {
                kind: PhaseKind::Exhale,
                min_duration_ms: 2000,
                max_duration_ms: 8000,
            },
            PhaseLimit {
                kind: PhaseKind::HoldIn,
                min_duration_ms: 1000,
                max_duration_ms: 10000,
            },
        ])
    }

    #[test]
    fn a_saved_exercise_becomes_a_validated_payload() {
        let input = r#"{
            "name": "My evening four-seven",
            "summary": "For getting to sleep.",
            "goal": "sleep",
            "rounds": 2,
            "stages": [{
                "cycles": 6,
                "phases": [
                    { "kind": "inhale", "passage": "nose", "seconds": 4 },
                    { "kind": "hold", "seconds": 7 },
                    { "kind": "exhale", "passage": "mouth", "seconds": 8 }
                ]
            }]
        }"#;
        let Some(pb::chat_response::Payload::SavedExercise(draft)) = payload(input, &limits())
        else {
            panic!("a valid saved-exercise payload");
        };
        assert_eq!(draft.name, "My evening four-seven");
        assert_eq!(draft.goal, pb::TechniqueGoal::Sleep as i32);
        assert_eq!(draft.rounds, 2);
        assert_eq!(draft.stages[0].cycles, 6);
        assert_eq!(
            draft.stages[0].phases[1].movement,
            Some(pb::draft_phase::Movement::Hold(pb::Hold {}))
        );
    }

    #[test]
    fn invented_vocabulary_refuses_the_whole_draft() {
        for invented in [
            r#"{ "name": "n", "goal": "transcendence", "stages": [] }"#,
            r#"{ "name": "n", "goal": "calm", "stages": [{ "phases": [{ "kind": "sigh", "seconds": 4 }] }] }"#,
            r#"{ "name": "n", "goal": "calm", "stages": [{ "phases": [{ "kind": "inhale", "passage": "ears", "seconds": 4 }] }] }"#,
            r#"{ "name": "n", "goal": "calm", "stages": [], "intensity": "maximum" }"#,
            r#"{ "goal": "calm", "stages": [] }"#,
        ] {
            assert!(draft(invented).is_none(), "`{invented}` should be refused");
        }
    }

    #[test]
    fn counts_clamp_before_validation() {
        let input = r#"{
            "name": "n",
            "goal": "calm",
            "rounds": 99,
            "stages": [{ "cycles": 500, "phases": [{ "kind": "hold", "seconds": 4 }] }]
        }"#;
        let draft = draft(input).expect("a shaped draft");
        assert_eq!(draft.rounds, u32::try_from(MAX_ROUNDS).expect("positive"));
        assert_eq!(
            draft.stages[0].cycles,
            u32::try_from(MAX_CYCLES).expect("positive")
        );
    }

    #[test]
    fn an_unnamed_breath_passage_is_the_nose() {
        let input = r#"{ "name": "n", "goal": "calm", "stages": [{ "phases": [{ "kind": "inhale", "seconds": 4 }, { "kind": "exhale", "seconds": 4 }] }] }"#;
        let draft = draft(input).expect("a shaped draft");
        assert_eq!(
            draft.stages[0].phases[0].movement,
            Some(pb::draft_phase::Movement::Inhale(pb::Passage::Nose as i32))
        );
    }

    #[test]
    fn owning_validation_refuses_an_unsafe_duration() {
        let input = r#"{ "name": "n", "goal": "calm", "stages": [{ "phases": [{ "kind": "inhale", "seconds": 60 }, { "kind": "exhale", "seconds": 4 }] }] }"#;
        assert!(
            draft(input).is_some(),
            "the model vocabulary shapes cleanly"
        );
        assert!(
            payload(input, &limits()).is_none(),
            "the owning limits refuse it"
        );
    }
}
