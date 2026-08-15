use super::super::model::ToolSpec;
use crate::proto::ond::v1 as pb;

/// The model-facing name used by both the schema and dispatcher.
pub(super) const NAME: &str = "offer_bolt_test";

/// The `offer_bolt_test` tool as Chat declares it.
///
/// No input at all is the whole safety story: an empty object has nothing to
/// invent or clamp. It closes the loop the prompt opens when a fresh BOLT score
/// would materially change what the coach can say.
pub(super) fn spec() -> ToolSpec {
    ToolSpec {
        name: NAME,
        description: "Offer to start the breath-hold (BOLT) test. Call it at most once, \
             after your prose, and only where a fresh score would change what you can \
             say — chiefly when they have never taken one. Never present it as a \
             diagnosis.",
        input_schema: serde_json::json!({
            "type": "object",
            "additionalProperties": false,
            "properties": {}
        }),
    }
}

/// The BOLT payload this input supports.
///
/// Checked as a JSON object rather than an empty serde struct because serde
/// also accepts a sequence for a unit-like shape. The schema permits precisely
/// an empty object, so there is no useful leniency to preserve.
pub(super) fn payload(input_json: &str) -> Option<pb::chat_response::Payload> {
    let input: serde_json::Value = serde_json::from_str(input_json).ok()?;
    input
        .as_object()
        .filter(|fields| fields.is_empty())
        .map(|_| pb::chat_response::Payload::BoltTest(pb::BoltTestOffer {}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_an_empty_object_and_nothing_else() {
        assert!(payload("{}").is_some());
        assert!(payload("  { }  ").is_some());

        for invented in [
            r#"{ "reason": "they have never taken one" }"#,
            "{ not json",
            "null",
            "[]",
        ] {
            assert!(
                payload(invented).is_none(),
                "`{invented}` should be refused"
            );
        }
    }
}
