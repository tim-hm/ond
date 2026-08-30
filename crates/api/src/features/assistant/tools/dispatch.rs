//! The only cross-tool match in the feature. Declaring a tool and validating
//! its call live here together on purpose: a tool added to the spec list
//! cannot reach the model without also being given a payload path.

use super::{bolt, exercise, saved_exercise};
use crate::features::assistant::model::ToolSpec;
use crate::features::technique::types::Technique;
use crate::features::user_technique::types::PhaseLimits;
use crate::proto::ond::v1 as pb;

/// Every tool Chat declares, in stable provider-cache order.
///
/// The same modules whose names appear in [`dispatch`] construct these specs,
/// so adding a tool cannot update the declaration without also giving its call
/// a validation and payload path.
pub(in crate::features::assistant) fn specs() -> Vec<ToolSpec> {
    vec![exercise::spec(), bolt::spec(), saved_exercise::spec()]
}

/// Validates one completed model call and converts it into its wire payload.
///
/// Unknown names and invalid inputs are ordinary `None`: the surrounding prose
/// has already streamed, so refusing a card must not refuse the answer.
pub(in crate::features::assistant) fn dispatch(
    name: &str,
    input_json: &str,
    catalogue: &[Technique],
    limits: &PhaseLimits,
) -> Option<pb::chat_response::Payload> {
    match name {
        exercise::NAME => exercise::payload(input_json, catalogue),
        bolt::NAME => bolt::payload(input_json),
        saved_exercise::NAME => saved_exercise::payload(input_json, limits),
        _ => None,
    }
}

/// A count inside its ceiling, and never zero: both tools read counts the
/// model wrote, and every one of them is bounded by the same limits.
pub(super) fn clamped(value: i64, ceiling: i32) -> Option<u32> {
    u32::try_from(value.clamp(1, i64::from(ceiling))).ok()
}

/// Seconds as wire milliseconds inside an inclusive range.
///
/// The cast is safe after the f64 clamp into bounds already represented by
/// `i32`; the standard library has no checked float-to-integer conversion.
#[allow(clippy::cast_possible_truncation)]
pub(super) fn clamped_ms(seconds: f64, min: i32, max: i32) -> i32 {
    (seconds * 1000.0)
        .round()
        .clamp(f64::from(min), f64::from(max)) as i32
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;
    use crate::features::technique::types::{PhaseKind, TechniqueGoal};
    use crate::features::user_technique::types::PhaseLimit;

    fn catalogue() -> Vec<Technique> {
        vec![Technique::test("box-breathing", TechniqueGoal::Calm)]
    }

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
        ])
    }

    #[test]
    fn dispatches_an_exercise_offer() {
        assert!(matches!(
            dispatch(
                exercise::NAME,
                r#"{ "technique_slug": "box-breathing" }"#,
                &catalogue(),
                &limits()
            ),
            Some(pb::chat_response::Payload::Offer(_))
        ));
    }

    #[test]
    fn dispatches_a_bolt_offer() {
        assert!(matches!(
            dispatch(bolt::NAME, "{}", &catalogue(), &limits()),
            Some(pb::chat_response::Payload::BoltTest(_))
        ));
    }

    #[test]
    fn dispatches_a_saved_exercise_offer() {
        let input = r#"{
            "name": "Evening four",
            "goal": "sleep",
            "stages": [{ "phases": [
                { "kind": "inhale", "passage": "nose", "seconds": 4 },
                { "kind": "exhale", "passage": "mouth", "seconds": 4 }
            ] }]
        }"#;
        assert!(matches!(
            dispatch(saved_exercise::NAME, input, &catalogue(), &limits()),
            Some(pb::chat_response::Payload::SavedExercise(_))
        ));
    }

    #[test]
    fn rejects_an_unknown_tool_name() {
        assert!(dispatch("grant_admin", "{}", &catalogue(), &limits()).is_none());
    }

    /// Stable, distinct specs are a provider-cache invariant. Reading them from
    /// the one public list also pins declaration order and catches a new module
    /// that was added without being declared.
    #[test]
    fn specs_are_stable_and_names_are_unique() {
        let first = specs();
        let second = specs();
        assert_eq!(first.len(), 3);
        assert_eq!(
            first
                .iter()
                .map(|tool| &tool.input_schema)
                .collect::<Vec<_>>(),
            second
                .iter()
                .map(|tool| &tool.input_schema)
                .collect::<Vec<_>>()
        );
        let names: HashSet<_> = first.iter().map(|tool| tool.name).collect();
        assert_eq!(names.len(), first.len());
    }
}
