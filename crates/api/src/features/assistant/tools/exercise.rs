//! The card that offers one catalogue exercise, optionally repaced. The slug
//! is checked against the catalogue rather than trusted, and every duration
//! and count is clamped into the ranges the catalogue seeds, so the offer can
//! only ever be something the app already plays.

use serde::Deserialize;

use super::super::model::ToolSpec;
use super::dispatch::{clamped, clamped_ms};
use crate::features::technique::types::{PlayableStage, Technique, resolve};
use crate::features::user_technique::types::{MAX_CYCLES, MAX_ROUNDS};
use crate::proto::ond::v1 as pb;

/// The model-facing name used by both the schema and dispatcher.
pub(super) const NAME: &str = "offer_exercise";

/// The `offer_exercise` tool as Chat declares it. The slug stays a free
/// string validated against the catalogue rather than an enum whose bytes
/// would change with the seed and invalidate the provider cache. Durations
/// use seconds — the prompt's vocabulary; only this module converts to wire ms.
pub(super) fn spec() -> ToolSpec {
    ToolSpec {
        name: NAME,
        description: "Offer to start one breathing exercise from the catalogue, \
             optionally with adjusted pacing. Call it at most once, after your \
             prose, and only when the conversation has settled on one exercise \
             worth doing now. Omit every optional field to offer the exercise \
             as catalogued.",
        input_schema: serde_json::json!({
            "type": "object",
            "required": ["technique_slug"],
            "additionalProperties": false,
            "properties": {
                "technique_slug": {
                    "type": "string",
                    "description": "A slug from the CATALOGUE section, exactly as written there."
                },
                "rounds": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 10,
                    "description": "How many rounds to offer. Omit for the catalogue's recommendation."
                },
                "stages": {
                    "type": "array",
                    "description": "One entry per stage of the exercise, in order. Omit to keep the catalogue pacing.",
                    "items": {
                        "type": "object",
                        "additionalProperties": false,
                        "properties": {
                            "cycles": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 99,
                                "description": "How many times this stage's phases repeat."
                            },
                            "phase_durations_seconds": {
                                "type": "array",
                                "items": { "type": "number" },
                                "description": "One duration per phase of this stage, in seconds, inside the ranges the catalogue shows."
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
struct OfferInput {
    technique_slug: String,
    #[serde(default)]
    rounds: Option<i64>,
    #[serde(default)]
    stages: Option<Vec<StageInput>>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StageInput {
    #[serde(default)]
    cycles: Option<i64>,
    #[serde(default)]
    phase_durations_seconds: Option<Vec<f64>>,
}

/// The exercise payload this input supports.
///
/// Anything invented returns `None`, while a real catalogue exercise is made
/// complete and clamped. Missing stage slots retain catalogue defaults, extra
/// slots are ignored, and an open-ended stage retains its authored count.
pub(super) fn payload(
    input_json: &str,
    catalogue: &[Technique],
) -> Option<pb::chat_response::Payload> {
    let input: OfferInput = serde_json::from_str(input_json).ok()?;
    let technique = resolve(catalogue, &input.technique_slug)?;

    let adjusted = input.rounds.is_some()
        || input.stages.as_ref().is_some_and(|stages| {
            stages.iter().any(|stage| {
                stage.cycles.is_some()
                    || stage
                        .phase_durations_seconds
                        .as_ref()
                        .is_some_and(|durations| !durations.is_empty())
            })
        });

    let overrides = if adjusted {
        Some(dialled_overrides(technique, &input)?)
    } else {
        None
    };
    Some(pb::chat_response::Payload::Offer(pb::ExerciseOffer {
        technique_slug: technique.slug.clone().into_string(),
        overrides,
    }))
}

fn dialled_overrides(technique: &Technique, input: &OfferInput) -> Option<pb::ExerciseOverrides> {
    Some(pb::ExerciseOverrides {
        stages: technique
            .stages
            .iter()
            .enumerate()
            .map(|(index, stage)| {
                dialled_stage(
                    stage,
                    input.stages.as_deref().and_then(|stages| stages.get(index)),
                )
            })
            .collect::<Option<Vec<_>>>()?,
        rounds: clamped(
            input
                .rounds
                .unwrap_or(i64::from(technique.recommended_rounds)),
            MAX_ROUNDS,
        )?,
    })
}

fn dialled_stage(stage: &PlayableStage, input: Option<&StageInput>) -> Option<pb::StageDialling> {
    let cycles = if stage.open_ended {
        u32::try_from(stage.cycles).ok()?
    } else {
        match input.and_then(|input| input.cycles) {
            Some(cycles) => clamped(cycles, MAX_CYCLES)?,
            None => u32::try_from(stage.cycles).ok()?,
        }
    };

    let phase_durations_ms = stage
        .phases
        .iter()
        .enumerate()
        .map(|(index, phase)| {
            let offered = input
                .and_then(|input| input.phase_durations_seconds.as_ref())
                .and_then(|durations| durations.get(index))
                .copied()
                .filter(|seconds| seconds.is_finite() && *seconds > 0.0);
            let duration_ms = offered.map_or(phase.duration_ms, |seconds| {
                clamped_ms(seconds, phase.min_duration_ms, phase.max_duration_ms)
            });
            u32::try_from(duration_ms).ok()
        })
        .collect::<Option<Vec<_>>>()?;

    Some(pb::StageDialling {
        phase_durations_ms,
        cycles,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::technique::types::TechniqueGoal;

    fn catalogue() -> Vec<Technique> {
        vec![
            Technique::test("box-breathing", TechniqueGoal::Calm),
            Technique::test("four-seven-eight", TechniqueGoal::Sleep),
        ]
    }

    fn exercise_offer(input: &str, catalogue: &[Technique]) -> Option<pb::ExerciseOffer> {
        match payload(input, catalogue) {
            Some(pb::chat_response::Payload::Offer(offer)) => Some(offer),
            _ => None,
        }
    }

    #[test]
    fn a_full_offer_comes_back_complete_and_clamped() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "rounds": 3,
            "stages": [{ "cycles": 6, "phase_durations_seconds": [5, 3] }]
        }"#;
        let offer = exercise_offer(input, &catalogue()).expect("a valid offer");
        assert_eq!(offer.technique_slug, "box-breathing");
        let overrides = offer.overrides.expect("adjustments were asked for");
        assert_eq!(overrides.rounds, 3);
        assert_eq!(overrides.stages.len(), 1);
        assert_eq!(overrides.stages[0].cycles, 6);
        assert_eq!(overrides.stages[0].phase_durations_ms, vec![5000, 3000]);
    }

    #[test]
    fn unresolvable_or_malformed_input_is_refused() {
        assert!(
            exercise_offer(r#"{ "technique_slug": "moon-breathing" }"#, &catalogue()).is_none()
        );
        assert!(exercise_offer("{ not json", &catalogue()).is_none());
        assert!(
            exercise_offer(
                r#"{ "technique_slug": "box-breathing", "intensity": "maximum" }"#,
                &catalogue()
            )
            .is_none()
        );
    }

    #[test]
    fn a_bare_offer_carries_no_overrides() {
        let offer = exercise_offer(r#"{ "technique_slug": "box-breathing" }"#, &catalogue())
            .expect("a valid offer");
        assert!(offer.overrides.is_none());
        let offer = exercise_offer(
            r#"{ "technique_slug": "box-breathing", "stages": [] }"#,
            &catalogue(),
        )
        .expect("a valid offer");
        assert!(offer.overrides.is_none());
    }

    #[test]
    fn out_of_range_values_clamp_to_the_catalogue() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "rounds": 99,
            "stages": [{ "cycles": 500, "phase_durations_seconds": [60, 0.1] }]
        }"#;
        let overrides = exercise_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjusted");
        assert_eq!(
            overrides.rounds,
            u32::try_from(MAX_ROUNDS).expect("positive")
        );
        assert_eq!(
            overrides.stages[0].cycles,
            u32::try_from(MAX_CYCLES).expect("positive")
        );
        assert_eq!(overrides.stages[0].phase_durations_ms, vec![8000, 2000]);
    }

    #[test]
    fn missing_slots_use_defaults_and_extras_are_ignored() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [
                { "phase_durations_seconds": [6] },
                { "cycles": 50 }
            ]
        }"#;
        let overrides = exercise_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjusted");
        assert_eq!(overrides.stages.len(), 1);
        assert_eq!(overrides.stages[0].cycles, 4);
        assert_eq!(overrides.stages[0].phase_durations_ms, vec![6000, 4000]);
    }

    #[test]
    fn unusable_durations_keep_the_default() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [{ "phase_durations_seconds": [-2, 0] }],
            "rounds": 2
        }"#;
        let overrides = exercise_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjusted");
        assert_eq!(overrides.stages[0].phase_durations_ms, vec![4000, 4000]);
    }

    #[test]
    fn an_open_ended_stage_keeps_its_catalogue_cycles() {
        let mut catalogue = catalogue();
        catalogue[0].stages[0].open_ended = true;
        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [{ "cycles": 50 }],
            "rounds": 2
        }"#;
        let overrides = exercise_offer(input, &catalogue)
            .expect("a valid offer")
            .overrides
            .expect("adjusted");
        assert_eq!(overrides.stages[0].cycles, 4);
    }
}
