//! The export speaks the database's vocabulary and the contract's, not Rust's.
//! Every serde rename here has a twin in the Swift decoder, and a rename lost
//! here fails at the far end of a generate step rather than in this crate.

use anyhow::{Context, Result};
use serde::Serialize;

use super::catalogue::{FOUNDATIONS, OCCASIONS, PROGRESSION, TECHNIQUES};
use super::types::{
    EvidenceGrade, OccasionSeed, ProgressionStepSeed, ReadingContentSeed, StageSeed, TechniqueGoal,
};

/// The whole of the curated reference data as JSON, each list in presentation
/// order, with a trailing newline like every other generated file. It exists so
/// the app and the drawings work from the numbers the database is seeded with.
/// It reads the four `const` lists and opens no connection. It carries the
/// occasions and the progression too, so a first launch works offline.
pub fn catalogue_json() -> Result<String> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Catalogue<'a> {
        techniques: Vec<TechniqueExport<'a>>,
        foundations: Vec<FoundationExport>,
        occasions: &'static [OccasionSeed],
        progression: &'static [ProgressionStepSeed],
        physiology: Physiology,
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct TechniqueExport<'a> {
        slug: &'static str,
        name: &'static str,
        summary: &'static str,
        mechanism: String,
        mechanism_content: ReadingContentSeed,
        evidence: String,
        evidence_content: ReadingContentSeed,
        evidence_grade: EvidenceGrade,
        safety_note: &'static str,
        preparation: String,
        preparation_content: ReadingContentSeed,
        goal: TechniqueGoal,
        stages: &'a [StageSeed],
        recommended_rounds: i32,
        requires_subscription: bool,
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct FoundationExport {
        slug: &'static str,
        question: &'static str,
        answer: String,
        answer_content: ReadingContentSeed,
    }

    /// The facts about a body that a client has to know to describe a session,
    /// carried here because Swift cannot depend on the [`physiology`] crate.
    /// `OndKit` keeps its own constant for ergonomics and asserts it against
    /// this value, which is the drift test that crate deleted, restored where
    /// it is still needed.
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Physiology {
        fast_breathing_cycle_ms: i32,
    }

    let techniques = TECHNIQUES
        .iter()
        .map(|technique| TechniqueExport {
            slug: technique.slug,
            name: technique.name,
            summary: technique.summary,
            mechanism: technique.mechanism.plain_text(),
            mechanism_content: technique.mechanism,
            evidence: technique.evidence.plain_text(),
            evidence_content: technique.evidence,
            evidence_grade: technique.evidence_grade,
            safety_note: technique.safety_note,
            preparation: technique.preparation.plain_text(),
            preparation_content: technique.preparation,
            goal: technique.goal,
            stages: technique.stages,
            recommended_rounds: technique.recommended_rounds,
            requires_subscription: technique.requires_subscription,
        })
        .collect();
    let foundations = FOUNDATIONS
        .iter()
        .map(|topic| FoundationExport {
            slug: topic.slug,
            question: topic.question,
            answer: topic.answer.plain_text(),
            answer_content: topic.answer,
        })
        .collect();

    let mut json = serde_json::to_string_pretty(&Catalogue {
        techniques,
        foundations,
        occasions: OCCASIONS,
        progression: PROGRESSION,
        physiology: Physiology {
            fast_breathing_cycle_ms: physiology::FAST_BREATHING_CYCLE_MS,
        },
    })
    .context("failed to serialise the curated reference data")?;
    json.push('\n');
    Ok(json)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The committed export, parsed. The tests below read it, and none cares how
    /// it was produced.
    fn exported() -> serde_json::Value {
        serde_json::from_str(&catalogue_json().expect("the catalogue serialises"))
            .expect("the export is valid JSON")
    }

    /// The export is what the app's drawings and the marketing site's are both
    /// derived from, so a technique missing from it is a technique that silently
    /// stops having a picture. Checking every slug and every phase kind rather
    /// than the count alone: a serialiser that dropped `stages` would still
    /// produce an entry per technique.
    #[test]
    fn the_export_carries_every_technique_and_every_phase() {
        let json = exported();
        let exported = json["techniques"]
            .as_array()
            .expect("the export holds a technique array");

        assert_eq!(exported.len(), TECHNIQUES.len());

        for (exported, seeded) in exported.iter().zip(TECHNIQUES) {
            assert_eq!(exported["slug"], seeded.slug);

            let stages = exported["stages"]
                .as_array()
                .expect("a technique holds a stage array");
            assert_eq!(stages.len(), seeded.stages.len(), "`{}`", seeded.slug);

            for (stage, seeded) in stages.iter().zip(seeded.stages) {
                let phases = stage["phases"]
                    .as_array()
                    .expect("a stage holds a phase array");
                assert_eq!(phases.len(), seeded.phases.len(), "`{}`", exported["slug"]);

                for (phase, seeded) in phases.iter().zip(seeded.phases) {
                    assert_eq!(phase["durationMs"], seeded.duration_ms);
                }
            }
        }
    }

    /// Where `slug` sits in the export, which is where it sits in
    /// `TECHNIQUES`. Looked up rather than written down: curation reorders the
    /// catalogue and a fixed index would go on asserting about its neighbour.
    fn technique_index(slug: &str) -> usize {
        TECHNIQUES
            .iter()
            .position(|technique| technique.slug == slug)
            .unwrap_or_else(|| panic!("the catalogue seeds `{slug}`"))
    }

    /// The vocabulary the export speaks is the database's and the contract's,
    /// not Rust's. A serde rename lost here would leave the Swift side decoding
    /// `Inhale` where it expects `INHALE`, which fails at the far end of a
    /// generate step rather than here.
    #[test]
    fn the_export_speaks_the_contract_vocabulary() {
        let json = exported();

        assert_eq!(json["techniques"][0]["goal"], "CALM");
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["kind"],
            "INHALE"
        );
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][1]["kind"],
            "HOLD_IN"
        );
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["passage"],
            "NOSE"
        );
        assert_eq!(json["techniques"][0]["evidenceGrade"], "MODERATE");
        // Box breathing shapes nothing, and the key is present saying so rather
        // than absent: a key set that varies with the data is the worse artefact
        // to diff, and `Option<Manner>` without a skip is what keeps it steady.
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][0]["manner"],
            serde_json::Value::Null
        );
        // Both cadence keys on the same terms, and null for the same reason:
        // box breathing's inhale authors neither, and a reader taking an
        // absent key for an authored zero would drop the derived turn from
        // every phase.
        for key in ["turnGapMs", "hapticPattern"] {
            assert_eq!(
                json["techniques"][0]["stages"][0]["phases"][0].get(key),
                Some(&serde_json::Value::Null)
            );
        }
        // And the same two where a table authored them, so the keys are
        // checked carrying a value and not only carrying null. The sigh's sip
        // authors both, and its gap is an authored zero.
        assert_eq!(
            json["techniques"][0]["stages"][0]["phases"][1]["turnGapMs"],
            150
        );
        let sigh = technique_index("physiological-sigh");
        let sip = &json["techniques"][sigh]["stages"][0]["phases"][1];
        assert_eq!(sip["turnGapMs"], 0);
        assert_eq!(sip["hapticPattern"], "sip");
        // And one that is shaped, so the label is checked and not only the
        // absence of one — a serialiser that emitted every manner as null would
        // satisfy the line above.
        let cooling = technique_index("cooling-breath");
        assert_eq!(
            json["techniques"][cooling]["stages"][0]["phases"][0]["manner"],
            "CURLED_TONGUE"
        );

        // Swept rather than sampled, unlike the technique assertions above: the
        // first occasion is whichever the curation happens to lead with, so
        // naming one would break on a reorder while proving no more. A loop
        // rather than `all`, so a failure names the occasion that broke it —
        // over seventeen entries, "false is not true" is not a message.
        for occasion in json["occasions"]
            .as_array()
            .expect("the export holds an occasion array")
        {
            let surface = occasion["surface"].as_str().expect("a surface label");
            let register = occasion["register"].as_str().expect("a register label");
            assert!(
                ["FULL_SCREEN", "DISCREET"].contains(&surface),
                "`{}` exports surface `{surface}`",
                occasion["slug"]
            );
            assert!(
                ["PLAIN", "PLAYFUL"].contains(&register),
                "`{}` exports register `{register}`",
                occasion["slug"]
            );
        }
    }

    /// The routing half of the export, which nothing reads until a launch out of
    /// range needs it — and which therefore has no other chance to go wrong
    /// loudly. The seed writing the database cannot catch a mistake here: it
    /// binds these constants directly and would agree with itself whatever the
    /// serialiser did.
    #[test]
    fn the_export_carries_the_routing_layer() {
        let json = exported();

        let occasions = json["occasions"]
            .as_array()
            .expect("the export holds an occasion array");
        assert_eq!(occasions.len(), OCCASIONS.len());

        for (exported, seeded) in occasions.iter().zip(OCCASIONS) {
            assert_eq!(exported["slug"], seeded.slug);
            assert_eq!(exported["techniqueSlug"], seeded.technique_slug);
            assert_eq!(exported["durationMs"], seeded.duration_ms);
            assert_eq!(
                exported["phaseDurationsMs"],
                serde_json::json!(seeded.phase_durations_ms),
                "`{}`",
                seeded.slug
            );
        }

        let foundations = json["foundations"]
            .as_array()
            .expect("the export holds a foundation array");
        assert_eq!(foundations.len(), FOUNDATIONS.len());
        for (exported, seeded) in foundations.iter().zip(FOUNDATIONS) {
            assert_eq!(exported["slug"], seeded.slug);
            assert_eq!(exported["answer"], seeded.answer.plain_text());
            assert_eq!(
                exported["answerContent"],
                serde_json::to_value(seeded.answer).expect("reading content serialises")
            );
        }

        let progression = json["progression"]
            .as_array()
            .expect("the export holds a progression array");
        assert_eq!(progression.len(), PROGRESSION.len());
        for (exported, seeded) in progression.iter().zip(PROGRESSION) {
            assert_eq!(exported["techniqueSlug"], seeded.technique_slug);
        }
    }
}
