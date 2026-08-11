//! The one tool the chat declares, and the guard that believes as little of a
//! call to it as possible.
//!
//! Both halves of the tool live here on `prompt`/`parse` terms: the spec is
//! what we ask the model to do, `validate_offer` is what we believe of the
//! answer, and only the second half is load-bearing for safety. The spec must
//! be byte-stable across calls — see [`crate::features::assistant::model::ToolSpec`] —
//! so nothing in it derives from the catalogue or the caller.

use serde::Deserialize;

use super::model::ToolSpec;
use crate::features::technique::types::{PlayableStage, Technique, resolve};
use crate::features::user_technique::types::{MAX_CYCLES, MAX_ROUNDS};
use crate::proto::ond::v1 as pb;

/// The name the wire and the accumulator match on.
pub const OFFER_EXERCISE: &str = "offer_exercise";

/// The second tool, on the same terms as the first.
pub const OFFER_BOLT_TEST: &str = "offer_bolt_test";

/// The `offer_bolt_test` tool as the chat declares it.
///
/// No input at all, which is the whole of its safety story: an empty object has
/// nothing to invent and nothing to clamp, so [`validate_bolt_offer`] asks only
/// whether the model managed to send one.
///
/// It closes a loop the prefix already opens. The coach is briefed at length on
/// how to read a BOLT score and has never been able to do anything about not
/// having one except describe where the test lives. `bolt.count` is in the
/// practice block, so "chiefly when they have never taken one" is a rule the
/// model can actually check rather than a hope.
pub fn offer_bolt_test_tool() -> ToolSpec {
    ToolSpec {
        name: OFFER_BOLT_TEST,
        description: "Offer to start the breath-hold (BOLT) test. Call it at most once, \
             after your prose, and only where a fresh score would change what you can \
             say — chiefly when they have never taken one. Never present it as a \
             diagnosis, and never call it in the same reply as offer_exercise.",
        input_schema: serde_json::json!({
            "type": "object",
            "additionalProperties": false,
            "properties": {}
        }),
    }
}

/// The BOLT offer this input supports, or `None`.
///
/// The tool being called is the whole payload, so this asks one question: did
/// the model send the empty object its schema declares. Anything else is a model
/// inventing vocabulary, refused on [`validate_offer`]'s terms.
///
/// Checked as a `Value` rather than parsed into an empty struct with
/// `deny_unknown_fields`, which is the shape the rest of this file uses: serde
/// will happily read a *sequence* into a struct, so `[]` deserialises into an
/// empty one and passes. There is nothing here for a lenient parse to buy —
/// the payload carries no data either way — so the strict reading is free.
pub fn validate_bolt_offer(input_json: &str) -> Option<pb::BoltTestOffer> {
    let input: serde_json::Value = serde_json::from_str(input_json).ok()?;
    input
        .as_object()
        .filter(|fields| fields.is_empty())
        .map(|_| pb::BoltTestOffer {})
}

/// The `offer_exercise` tool as the chat declares it.
///
/// The slug is a free string validated server-side rather than an enum of the
/// seeded slugs: an enum would couple the schema bytes to the seed — invalidating
/// the provider cache on every catalogue change — and buys nothing
/// [`validate_offer`]'s resolver does not already guarantee. Durations are
/// seconds because that is how the prompt's pattern lines describe every
/// exercise; the wire's milliseconds are this module's conversion to make.
pub fn offer_exercise_tool() -> ToolSpec {
    ToolSpec {
        name: OFFER_EXERCISE,
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

/// What the model may put in an `offer_exercise` call. Unknown fields fail the
/// parse — a model inventing vocabulary is not one to negotiate with.
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

/// The offer this input supports, or `None` — and `None` is the ordinary
/// answer to anything invented, on `parse_recommendations`' exact terms: the
/// prose the model wrote alongside it still streams, so a dropped offer costs
/// a card, never an answer.
///
/// Everything that survives is complete and clamped: one [`pb::StageDialling`]
/// per catalogue stage in play order, every slot carrying either the model's
/// value clamped into the phase's own min/max — cycles into `1..=MAX_CYCLES`,
/// rounds into `1..=MAX_ROUNDS` — or the catalogue default. The client applies
/// it wholesale, exactly as the proto promises. An open-ended stage keeps its
/// catalogue cycles whatever the model asked, mirroring the dial UI. Extra
/// stage entries are ignored and missing ones filled with defaults, so a model
/// that miscounted stages adjusts what it named and invents nothing.
pub fn validate_offer(input_json: &str, catalogue: &[Technique]) -> Option<pb::ExerciseOffer> {
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

    Some(pb::ExerciseOffer {
        technique_slug: technique.slug.clone(),
        overrides,
    })
}

/// The complete dialling this input asks for, or `None` where a catalogue
/// value would not narrow onto the wire — corrupt seed data the schema's
/// `CHECK`s make unreachable, answered by dropping the offer rather than
/// serving a number nobody chose.
fn dialled_overrides(technique: &Technique, input: &OfferInput) -> Option<pb::ExerciseOverrides> {
    Some(pb::ExerciseOverrides {
        stages: technique
            .stages
            .iter()
            .enumerate()
            .map(|(index, stage)| {
                dialled_stage(stage, input.stages.as_deref().and_then(|s| s.get(index)))
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

/// One stage's complete dialling: the model's usable values where it gave any,
/// the catalogue's where it did not.
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

/// The model's seconds as wire milliseconds, clamped into the phase's own
/// range — the feature's one float-to-integer step.
///
/// The clamp runs in f64 space, so by the time of the cast the value sits
/// inside `[min, max]` ⊆ `i32` and the truncation the lint fears cannot
/// happen; there is no checked float conversion in std to say it with.
#[allow(clippy::cast_possible_truncation)]
fn clamped_ms(seconds: f64, min: i32, max: i32) -> i32 {
    (seconds * 1000.0)
        .round()
        .clamp(f64::from(min), f64::from(max)) as i32
}

/// A model integer clamped into `1..=ceiling`, as the wire's unsigned type.
fn clamped(value: i64, ceiling: i32) -> Option<u32> {
    u32::try_from(value.clamp(1, i64::from(ceiling))).ok()
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

    /// The happy path: a resolvable slug with adjustments comes back complete —
    /// every stage, every phase — with the model's values clamped in.
    #[test]
    fn a_full_offer_comes_back_complete_and_clamped() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "rounds": 3,
            "stages": [{ "cycles": 6, "phase_durations_seconds": [5, 3] }]
        }"#;

        let offer = validate_offer(input, &catalogue()).expect("a valid offer");
        assert_eq!(offer.technique_slug, "box-breathing");

        let overrides = offer.overrides.expect("adjustments were asked for");
        assert_eq!(overrides.rounds, 3);
        assert_eq!(overrides.stages.len(), 1, "one entry per catalogue stage");
        assert_eq!(overrides.stages[0].cycles, 6);
        assert_eq!(overrides.stages[0].phase_durations_ms, vec![5000, 3000]);
    }

    /// The whole reason this function exists: a slug the catalogue does not
    /// hold — free text from the model's imagination — never becomes an offer.
    #[test]
    fn an_unresolvable_slug_is_refused() {
        let input = r#"{ "technique_slug": "moon-breathing" }"#;
        assert!(validate_offer(input, &catalogue()).is_none());
    }

    /// Malformed input is refused whole rather than salvaged: JSON that does
    /// not parse, and vocabulary the schema never declared.
    #[test]
    fn malformed_input_is_refused() {
        assert!(validate_offer("{ not json", &catalogue()).is_none());
        assert!(
            validate_offer(
                r#"{ "technique_slug": "box-breathing", "intensity": "maximum" }"#,
                &catalogue()
            )
            .is_none()
        );
    }

    /// A slug alone is the ordinary offer: as catalogued, no overrides at all.
    #[test]
    fn a_bare_offer_carries_no_overrides() {
        let input = r#"{ "technique_slug": "box-breathing" }"#;
        let offer = validate_offer(input, &catalogue()).expect("a valid offer");
        assert!(offer.overrides.is_none());

        let empty_stages = r#"{ "technique_slug": "box-breathing", "stages": [] }"#;
        let offer = validate_offer(empty_stages, &catalogue()).expect("a valid offer");
        assert!(offer.overrides.is_none(), "empty adjustments are none");
    }

    /// Out-of-range values clamp to the catalogue's own bounds rather than
    /// refusing: the model chose a real exercise, and the person should get it
    /// at the nearest safe setting. The fixture's range is 2–8 seconds.
    #[test]
    fn out_of_range_values_clamp_to_the_catalogue() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "rounds": 99,
            "stages": [{ "cycles": 500, "phase_durations_seconds": [60, 0.1] }]
        }"#;

        let overrides = validate_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjustments were asked for");

        assert_eq!(
            overrides.rounds,
            u32::try_from(MAX_ROUNDS).expect("positive")
        );
        assert_eq!(
            overrides.stages[0].cycles,
            u32::try_from(MAX_CYCLES).expect("positive")
        );
        assert_eq!(
            overrides.stages[0].phase_durations_ms,
            vec![8000, 2000],
            "durations clamp into each phase's min/max"
        );
    }

    /// A short or missing entry fills with catalogue defaults; an extra entry
    /// is ignored. The model adjusts what it named and invents nothing.
    #[test]
    fn missing_slots_fill_with_defaults_and_extras_are_ignored() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [
                { "phase_durations_seconds": [6] },
                { "cycles": 50 }
            ]
        }"#;

        let overrides = validate_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjustments were asked for");

        assert_eq!(overrides.stages.len(), 1, "the extra entry is dropped");
        assert_eq!(
            overrides.stages[0].cycles, 4,
            "unnamed cycles keep the default"
        );
        assert_eq!(
            overrides.stages[0].phase_durations_ms,
            vec![6000, 4000],
            "the unnamed second phase keeps its default"
        );
    }

    /// Unusable numbers — negative, zero, NaN — leave their slot as catalogued
    /// rather than dropping the offer: the slot is the unbelievable part.
    #[test]
    fn unusable_durations_keep_the_default() {
        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [{ "phase_durations_seconds": [-2, 0] }],
            "rounds": 2
        }"#;

        let overrides = validate_offer(input, &catalogue())
            .expect("a valid offer")
            .overrides
            .expect("adjustments were asked for");

        assert_eq!(overrides.stages[0].phase_durations_ms, vec![4000, 4000]);
    }

    /// The BOLT offer has no input, so the whole of its validation is that the
    /// model sent the empty object its schema declares — and that anything else
    /// is refused rather than read as an empty one.
    #[test]
    fn the_bolt_offer_accepts_an_empty_object_and_nothing_else() {
        assert!(validate_bolt_offer("{}").is_some());
        assert!(validate_bolt_offer("  { }  ").is_some());

        for invented in [
            r#"{ "reason": "they have never taken one" }"#,
            "{ not json",
            "null",
            "[]",
        ] {
            assert!(
                validate_bolt_offer(invented).is_none(),
                "`{invented}` should be refused"
            );
        }
    }

    /// Both schemas must be byte-stable across calls: they sit ahead of the
    /// system prompt in the provider's cache hierarchy, so a schema that
    /// derived from the catalogue or the caller would invalidate the cached
    /// prefix on every single request.
    #[test]
    fn the_tool_schemas_are_the_same_bytes_every_time() {
        assert_eq!(
            offer_exercise_tool().input_schema,
            offer_exercise_tool().input_schema
        );
        assert_eq!(
            offer_bolt_test_tool().input_schema,
            offer_bolt_test_tool().input_schema
        );
        assert_ne!(offer_exercise_tool().name, offer_bolt_test_tool().name);
    }

    /// An open-ended stage keeps its catalogue cycles whatever the model
    /// asked: its count is presentational, and the dial UI refuses it too.
    #[test]
    fn an_open_ended_stage_keeps_its_catalogue_cycles() {
        let mut catalogue = catalogue();
        catalogue[0].stages[0].open_ended = true;

        let input = r#"{
            "technique_slug": "box-breathing",
            "stages": [{ "cycles": 50 }],
            "rounds": 2
        }"#;

        let overrides = validate_offer(input, &catalogue)
            .expect("a valid offer")
            .overrides
            .expect("adjustments were asked for");

        assert_eq!(overrides.stages[0].cycles, 4);
    }
}
