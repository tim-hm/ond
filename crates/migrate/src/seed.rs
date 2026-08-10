//! Seeds the technique catalogue, the breathing foundations, and the routes
//! into the catalogue — the occasion entries and the Start here progression.
//!
//! All of it is curated reference data, not user content, so it lives in code
//! and is reconciled into the database on every run. Editing a summary here and
//! re-running `mise run migrate` is the supported way to change them.
//!
//! Queries in this module are runtime `sqlx::query`, not the compile-time-checked
//! macros used in `crates/api`. This is the one crate that runs *before* the
//! schema exists, so it cannot depend on a prepared cache that could only have
//! been generated against a database this binary is responsible for creating.

use anyhow::{Context, Result};
use serde::Serialize;
use sqlx::PgPool;

use self::catalogue::{FOUNDATIONS, OCCASIONS, PROGRESSION, TECHNIQUES};

mod catalogue;

/// Mirrors the `technique_goal` Postgres enum declared in `0001_init.sql`.
///
/// A local copy rather than a shared type, on the same terms as the runtime
/// `sqlx::query` above: this crate is the one that creates the schema, so
/// depending on `api` to borrow two enums would drag the whole server — tonic,
/// axum, the generated protobuf — into the binary that has to run before any of
/// it can compile against a database.
///
/// What the copy buys is the part that matters. The seed now binds a value the
/// database's own type system accepts, so a mistyped label is a compile error
/// rather than a failed migration, and the vocabulary exists once here instead
/// of once as a string literal and again inside a test asserting the list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum TechniqueGoal {
    Calm,
    Sleep,
    Energy,
    Reset,
    Focus,
}

/// Mirrors the `phase_kind` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "phase_kind", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum PhaseKind {
    Inhale,
    HoldIn,
    Exhale,
    HoldOut,
}

/// Mirrors the `passage` Postgres enum, on the same terms as [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

/// Mirrors the `delivery_surface` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "delivery_surface", rename_all = "SCREAMING_SNAKE_CASE")]
enum DeliverySurface {
    FullScreen,
    Discreet,
}

/// One phase: its kind, where the air goes, the curated default, and the range a
/// dial may move it within.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PhaseSeed {
    kind: PhaseKind,
    /// `None` exactly for a hold, matching the column's `CHECK`. Unreachable in
    /// any other combination because the four constructors below are the only
    /// way to build one of these.
    passage: Option<Passage>,
    duration_ms: i32,
    min_duration_ms: i32,
    max_duration_ms: i32,
}

/// A run of cycles sharing one phase pattern.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StageSeed {
    phases: &'static [PhaseSeed],
    cycles: i32,
    /// Whether the person ends this stage rather than the clock.
    open_ended: bool,
}

/// One technique and the session it describes.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TechniqueSeed {
    slug: &'static str,
    name: &'static str,
    summary: &'static str,
    /// The caution this technique carries, empty where it carries none.
    ///
    /// **The phone renders it** as a full-screen warning between Begin and the
    /// countdown (`TechniqueWarningView`), accepted explicitly and silenceable
    /// per technique — silenced against this exact text, so rewording a note
    /// re-asks everyone who put it away. The watch and the assistant's
    /// fallback still show nothing; onboarding's consent step still names the
    /// hazards the whole catalogue shares. Blanking a note here removes the
    /// phone's warning for that technique.
    ///
    /// It is seeded, served over the wire, and asserted on anyway, because the
    /// copy is the expensive part and the plumbing is not. Two techniques carry
    /// a note and seven carry none, and that division is a judgement worth
    /// keeping under test while it is unread: `4-7-8` and the extended exhale
    /// used to warn about drowsiness and lost it deliberately — drowsiness
    /// arrives slowly enough to be somebody's own problem, and fainting in a
    /// bath does not.
    safety_note: &'static str,
    goal: TechniqueGoal,
    stages: &'static [StageSeed],
    /// How many times a default session repeats the whole stage list. Curated
    /// per technique, and one for everything that is a single cycle repeated —
    /// rounds only earn their name in a staged protocol.
    recommended_rounds: i32,
    /// Whether this one is behind önd Plus.
    ///
    /// **False for every technique, deliberately.** The whole catalogue is free
    /// while the featureset is still moving: locking seven of nine hid most of
    /// the app from the people whose use of it is meant to decide what belongs
    /// behind a subscription, which is the wrong way round. What actually sells
    /// is a question to answer from that use, before launch, not from a guess
    /// made ahead of it.
    ///
    /// The column, the flag, and every gate reading it stay exactly as they
    /// are. Restoring the catalogue gate is typing `true` here on whichever
    /// techniques the answer turns out to name.
    ///
    /// Stated per technique with no default behind it, because the column has
    /// none: a new technique cannot be added without someone deciding, which is
    /// the only way to stop the tiering drifting by accident in either
    /// direction — including back, one struct at a time, while it is meant to
    /// be uniform.
    requires_subscription: bool,
}

/// A phase with the dial range it may be moved within, inclusive.
///
/// A range of a single point means the phase is not adjustable, which is the
/// honest description of a hold the person ends themselves.
///
/// Four constructors rather than one taking a kind, so that a hold has nowhere
/// to put a passage and a breath cannot omit one — the same invariant the
/// column's `CHECK` states, held here by construction instead.
const fn inhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Inhale, passage, duration_ms, dial)
}

const fn exhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Exhale, passage, duration_ms, dial)
}

const fn hold_in(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldIn, duration_ms, dial)
}

const fn hold_out(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldOut, duration_ms, dial)
}

const fn breath(
    kind: PhaseKind,
    passage: Passage,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: Some(passage),
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
    }
}

const fn hold(kind: PhaseKind, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: None,
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
    }
}

const fn stage(phases: &'static [PhaseSeed], cycles: i32) -> StageSeed {
    StageSeed {
        phases,
        cycles,
        open_ended: false,
    }
}

/// A stage the clock does not end. One cycle by definition: repeating a hold
/// the person is already in charge of ending means nothing.
const fn open_ended_stage(phases: &'static [PhaseSeed]) -> StageSeed {
    StageSeed {
        phases,
        cycles: 1,
        open_ended: true,
    }
}

/// One question a beginner has, and the app's answer to it.
struct FoundationSeed {
    slug: &'static str,
    question: &'static str,
    answer: &'static str,
}

/// A named moment and the prescription it resolves to.
///
/// Flat rather than holding a `PrescriptionSeed`: the four fields below the
/// copy *are* the prescription, and a nested struct would buy a name the wire
/// already carries at the cost of a second brace level per entry.
struct OccasionSeed {
    slug: &'static str,
    name: &'static str,
    summary: &'static str,
    /// The technique this routes to, by the slug in [`TECHNIQUES`]. A foreign
    /// key onto `techniques.slug`, so a typo here fails the seed rather than
    /// reaching a client as a route to nothing.
    technique_slug: &'static str,
    /// The goal the moment borrows. Stated per occasion rather than read back
    /// through `technique_slug`, because what a moment is for must not move
    /// when a technique's primary grouping is re-curated.
    goal: TechniqueGoal,
    surface: DeliverySurface,
    /// What this occasion asks for, as a target a client fits whole cycles
    /// into rather than a stopwatch that cuts a breath short.
    duration_ms: i32,
}

/// One rung of the Start here progression.
struct ProgressionStepSeed {
    technique_slug: &'static str,
    /// Why this one at this point — what makes the order a progression rather
    /// than a list.
    note: &'static str,
}

/// The technique catalogue as JSON, in presentation order.
///
/// Exists so the drawings can be derived from the same numbers the database is
/// seeded with. The geometry that turns a technique into a figure lives in
/// Swift (`OndKit.TechniqueFigure`), the catalogue lives here, and something has
/// to cross between them — this crosses it once, into a committed artefact
/// `mise run check:generated` pins, rather than once per consumer.
///
/// Reads `TECHNIQUES` directly and never opens a connection: the catalogue is a
/// `const`, so exporting it must not require a database that the check running
/// in CI would then have to stand up.
///
/// Carries the techniques alone. The occasion entries and the progression are
/// server-read for now — nothing draws them, and putting them here would mean
/// a decoder in `OndKit` for a surface no client has yet. Whether the routes
/// should ship offline too is TIM-19's and TIM-128's question to answer when
/// they build against them.
///
/// Trailing newline because every other committed generated file has one and a
/// diff over a missing one is noise.
pub fn catalogue_json() -> Result<String> {
    #[derive(Serialize)]
    struct Catalogue {
        techniques: &'static [TechniqueSeed],
    }

    let mut json = serde_json::to_string_pretty(&Catalogue {
        techniques: TECHNIQUES,
    })
    .context("failed to serialise the technique catalogue")?;
    json.push('\n');
    Ok(json)
}

pub async fn run(pool: &PgPool) -> Result<()> {
    let mut tx = pool
        .begin()
        .await
        .context("failed to open seed transaction")?;

    for (index, technique) in TECHNIQUES.iter().enumerate() {
        upsert_technique(&mut tx, index, technique).await?;
    }

    for (index, topic) in FOUNDATIONS.iter().enumerate() {
        sqlx::query(
            r"INSERT INTO foundation_topics (slug, question, answer, sort_order)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (slug) DO UPDATE SET
                 question = EXCLUDED.question,
                 answer = EXCLUDED.answer,
                 sort_order = EXCLUDED.sort_order",
        )
        .bind(topic.slug)
        .bind(topic.question)
        .bind(topic.answer)
        .bind(i32::try_from(index).context("foundations are impossibly many")?)
        .execute(&mut *tx)
        .await
        .with_context(|| format!("failed to upsert foundation topic `{}`", topic.slug))?;
    }

    replace_routes(&mut tx).await?;

    tx.commit()
        .await
        .context("failed to commit seed transaction")?;
    tracing::info!(
        techniques = TECHNIQUES.len(),
        foundations = FOUNDATIONS.len(),
        occasions = OCCASIONS.len(),
        progression = PROGRESSION.len(),
        "reference data seeded"
    );

    Ok(())
}

/// Writes the occasion entries and the Start here progression, replacing both
/// wholesale.
///
/// Replaced rather than upserted, unlike the techniques and the foundations
/// above: nothing references an occasion or a step, and neither carries a
/// surrogate id worth preserving, so the seed can state the whole set instead
/// of reconciling it. That is what makes deleting an entry from this file
/// actually delete it — which the copy pass this working set is waiting for
/// (TIM-28) is going to want.
///
/// Runs after the techniques in the same transaction because both tables have a
/// foreign key onto `techniques.slug`.
async fn replace_routes(tx: &mut sqlx::PgTransaction<'_>) -> Result<()> {
    sqlx::query("DELETE FROM occasions")
        .execute(&mut **tx)
        .await
        .context("failed to clear the occasions")?;

    for (index, occasion) in OCCASIONS.iter().enumerate() {
        sqlx::query(
            r"INSERT INTO occasions
                 (slug, name, summary, technique_slug, goal, surface, duration_ms, sort_order)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
        )
        .bind(occasion.slug)
        .bind(occasion.name)
        .bind(occasion.summary)
        .bind(occasion.technique_slug)
        .bind(occasion.goal)
        .bind(occasion.surface)
        .bind(occasion.duration_ms)
        .bind(i32::try_from(index).context("occasions are impossibly many")?)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert occasion `{}`", occasion.slug))?;
    }

    sqlx::query("DELETE FROM progression_steps")
        .execute(&mut **tx)
        .await
        .context("failed to clear the progression")?;

    for (ordinal, step) in PROGRESSION.iter().enumerate() {
        let ordinal = i32::try_from(ordinal).context("the progression is impossibly long")?;

        sqlx::query(
            r"INSERT INTO progression_steps (ordinal, technique_slug, note)
               VALUES ($1, $2, $3)",
        )
        .bind(ordinal)
        .bind(step.technique_slug)
        .bind(step.note)
        .execute(&mut **tx)
        .await
        .with_context(|| {
            format!(
                "failed to insert progression step {ordinal} (`{}`)",
                step.technique_slug
            )
        })?;
    }

    Ok(())
}

/// Writes one technique and replaces its stages wholesale.
async fn upsert_technique(
    tx: &mut sqlx::PgTransaction<'_>,
    index: usize,
    technique: &TechniqueSeed,
) -> Result<()> {
    // `id` is only consumed on first insert; on conflict the existing row keeps
    // its id, so reseeding never invalidates a reference held elsewhere.
    let id: String = sqlx::query_scalar(
        r"INSERT INTO techniques
                 (id, slug, name, summary, safety_note, goal, sort_order,
                  recommended_rounds, requires_subscription)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
               ON CONFLICT (slug) DO UPDATE SET
                 name = EXCLUDED.name,
                 summary = EXCLUDED.summary,
                 safety_note = EXCLUDED.safety_note,
                 goal = EXCLUDED.goal,
                 sort_order = EXCLUDED.sort_order,
                 recommended_rounds = EXCLUDED.recommended_rounds,
                 requires_subscription = EXCLUDED.requires_subscription,
                 updated_at = now()
               RETURNING id",
    )
    .bind(cuid2::create_id())
    .bind(technique.slug)
    .bind(technique.name)
    .bind(technique.summary)
    .bind(technique.safety_note)
    .bind(technique.goal)
    .bind(i32::try_from(index).context("catalogue is impossibly large")?)
    .bind(technique.recommended_rounds)
    .bind(technique.requires_subscription)
    .fetch_one(&mut **tx)
    .await
    .with_context(|| format!("failed to upsert technique `{}`", technique.slug))?;

    // Replace rather than upsert: the session is an ordered list of ordered
    // lists, so a shorter edit would otherwise leave the trailing stages of the
    // previous version behind and lengthen the technique silently. The phases go
    // with them — their foreign key is the stage.
    sqlx::query("DELETE FROM technique_stages WHERE technique_id = $1")
        .bind(&id)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to clear stages for `{}`", technique.slug))?;

    for (ordinal, stage) in technique.stages.iter().enumerate() {
        let ordinal = i32::try_from(ordinal).context("session is impossibly long")?;

        sqlx::query(
            r"INSERT INTO technique_stages (technique_id, ordinal, cycles, open_ended)
               VALUES ($1, $2, $3, $4)",
        )
        .bind(&id)
        .bind(ordinal)
        .bind(stage.cycles)
        .bind(stage.open_ended)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert stage {ordinal} of `{}`", technique.slug))?;

        for (phase_ordinal, phase) in stage.phases.iter().enumerate() {
            sqlx::query(
                r"INSERT INTO technique_phases
                     (technique_id, stage_ordinal, ordinal, kind, passage,
                      duration_ms, min_duration_ms, max_duration_ms)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            )
            .bind(&id)
            .bind(ordinal)
            .bind(i32::try_from(phase_ordinal).context("cycle is impossibly long")?)
            .bind(phase.kind)
            .bind(phase.passage)
            .bind(phase.duration_ms)
            .bind(phase.min_duration_ms)
            .bind(phase.max_duration_ms)
            .execute(&mut **tx)
            .await
            .with_context(|| {
                format!(
                    "failed to insert phase {phase_ordinal} of stage {ordinal} of `{}`",
                    technique.slug
                )
            })?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The only slug the client is allowed to know about by name, and the only
    /// technique in the catalogue that has stages worth calling stages.
    const WIM_HOF: &str = "wim-hof-rounds";

    /// The committed export, parsed. Both tests below read it, and neither cares
    /// how it was produced.
    fn exported() -> serde_json::Value {
        serde_json::from_str(&catalogue_json().expect("the catalogue serialises"))
            .expect("the export is valid JSON")
    }

    /// The export is what the app's drawings and the marketing site's are both
    /// derived from, so a technique missing from it is a technique that silently
    /// stops having a picture. Checking every slug and every phase kind rather
    /// than the count alone: a serialiser that dropped `stages` would still
    /// produce nine entries.
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
    }

    /// The invariant the `passage` column's `CHECK` states, asserted over the
    /// export because that is the copy the drawings and the marketing site read:
    /// a breath always says where the air goes, and a hold never does, because
    /// air that is not moving goes nowhere.
    #[test]
    fn every_breath_names_a_passage_and_no_hold_does() {
        for technique in TECHNIQUES {
            for stage in technique.stages {
                for phase in stage.phases {
                    let breathing = matches!(phase.kind, PhaseKind::Inhale | PhaseKind::Exhale);
                    assert_eq!(
                        breathing,
                        phase.passage.is_some(),
                        "`{}` has a {:?} phase whose passage does not match",
                        technique.slug,
                        phase.kind
                    );
                }
            }
        }
    }

    /// The nostrils are the exercise rather than a decoration on it: without
    /// them alternate-nostril breathing is a 4:6:4:6 rhythm, which the catalogue
    /// already holds twice over. Seeded here rather than asserted by a
    /// client-side table keyed on this slug, which is what it was until the
    /// column existed.
    #[test]
    fn alternate_nostril_alternates() {
        let technique = TECHNIQUES
            .iter()
            .find(|technique| technique.slug == "alternate-nostril")
            .expect("the catalogue holds alternate-nostril breathing");

        assert_eq!(
            technique.stages[0]
                .phases
                .iter()
                .map(|phase| phase.passage)
                .collect::<Vec<_>>(),
            vec![
                Some(Passage::LeftNostril),
                Some(Passage::RightNostril),
                Some(Passage::RightNostril),
                Some(Passage::LeftNostril),
            ]
        );
    }

    /// Everything is free, and it is one line of this file away from not being
    /// — a `true` typed into one struct takes a technique back off everybody
    /// while the catalogue is meant to be uniform, and reads as a decision
    /// somebody made rather than the typo it would be.
    ///
    /// The whole-catalogue answer is the thing to assert, not a count: what
    /// this pins is that no technique is singled out, which is exactly the
    /// property a per-struct field cannot hold on its own.
    #[test]
    fn no_technique_is_behind_a_subscription() {
        let gated: Vec<_> = TECHNIQUES
            .iter()
            .filter(|technique| technique.requires_subscription)
            .map(|technique| technique.slug)
            .collect();

        assert!(
            gated.is_empty(),
            "the catalogue is free at every technique, and these are not: {gated:?}"
        );
    }

    /// The safety half of the old free-tier test, on the footing that outlived
    /// it. A `safety_note` means "this one can hurt you mid-breath", and the
    /// consent for that lives in onboarding — a screen somebody taps through in
    /// January and walks in on the strength of in March.
    ///
    /// The path that must not depend on that screen having been read is no
    /// longer the free pair, because there is no free pair. It is
    /// [`PROGRESSION`]: the four this app walks a beginner down, in order,
    /// having told them to start here. Somebody following the app's own
    /// instructions is the one person who has decided nothing, and nothing on
    /// that route may carry a caution that has to interrupt a session.
    ///
    /// The two that do carry one — bellows breath and the Wim Hof rounds — are
    /// reached by choosing them off the catalogue, which is a decision, and on
    /// the phone the note now stands as a full-screen warning between that
    /// choice and the countdown (`TechniqueWarningView`), accepted explicitly
    /// and silenceable per technique. The watch does not gate its own starts
    /// yet. The progression still has to stay clean: it is the one route
    /// through the app that asks nothing of the person choosing, and it should
    /// interrupt them with nothing either.
    #[test]
    fn the_progression_cannot_go_wrong() {
        for step in PROGRESSION {
            let technique = TECHNIQUES
                .iter()
                .find(|technique| technique.slug == step.technique_slug)
                .expect("every progression step names a technique in the catalogue");

            assert!(
                technique.safety_note.is_empty(),
                "`{}` is on the progression and carries a safety note",
                technique.slug
            );
        }
    }

    /// A technique with no stages — or a stage with no phases — would leave the
    /// client with an empty animation loop and nothing to advance through. The
    /// service rejects both at read time; catching it here names the technique.
    #[test]
    fn every_technique_is_a_playable_session() {
        for technique in TECHNIQUES {
            assert!(
                !technique.stages.is_empty(),
                "`{}` has no stages",
                technique.slug
            );
            assert!(
                technique.recommended_rounds > 0,
                "`{}` recommends no rounds",
                technique.slug
            );

            for (ordinal, stage) in technique.stages.iter().enumerate() {
                assert!(
                    !stage.phases.is_empty(),
                    "stage {ordinal} of `{}` has no phases",
                    technique.slug
                );
                assert!(
                    stage.cycles > 0,
                    "stage {ordinal} of `{}` plays no cycles",
                    technique.slug
                );
            }
        }
    }

    /// `slug` is the key the iOS client pins its artwork and haptics to, and the
    /// upsert is keyed on it — a duplicate would make the seed order decide
    /// which definition wins.
    #[test]
    fn slugs_are_unique() {
        let mut seen = std::collections::HashSet::new();
        for technique in TECHNIQUES {
            assert!(
                seen.insert(technique.slug),
                "duplicate slug `{}`",
                technique.slug
            );
        }
    }

    /// The `technique_phases_duration_within_range` CHECK in `0003` would reject
    /// these at write time, and a client rendering a dial from a range that does
    /// not contain its own starting value has nowhere to put the handle.
    #[test]
    fn every_dial_range_contains_its_default() {
        for technique in TECHNIQUES {
            for stage in technique.stages {
                for phase in stage.phases {
                    assert!(
                        phase.min_duration_ms > 0,
                        "`{}` has a non-positive {:?} minimum",
                        technique.slug,
                        phase.kind
                    );
                    assert!(
                        phase.min_duration_ms <= phase.duration_ms
                            && phase.duration_ms <= phase.max_duration_ms,
                        "`{}` has a {:?} default of {}ms outside its {}–{}ms range",
                        technique.slug,
                        phase.kind,
                        phase.duration_ms,
                        phase.min_duration_ms,
                        phase.max_duration_ms
                    );
                }
            }
        }
    }

    /// An open-ended stage stops the session clock until the person taps, so one
    /// seeded by accident would strand them on a screen that never advances. The
    /// retention in the Wim Hof-style protocol is the only place it belongs, and
    /// it is a single emptied-lung hold — anything else marked open-ended is a
    /// mistake, and so is the retention losing the flag.
    ///
    /// The breath either side of it is pinned here too, and that is the half
    /// worth keeping: the retention has to be entered on an exhale and left on
    /// an inhale, and neither of those breaths may live inside the open-ended
    /// stage, because a phase inside one is a phase the clock never ends. The
    /// stage before is the deep breath that the fast sequence used to run
    /// straight past.
    #[test]
    fn only_the_wim_hof_retention_is_open_ended() {
        for technique in TECHNIQUES {
            for (ordinal, stage) in technique.stages.iter().enumerate() {
                if !stage.open_ended {
                    continue;
                }

                assert_eq!(
                    technique.slug, WIM_HOF,
                    "`{}` has an unexpected open-ended stage",
                    technique.slug
                );
                assert_eq!(
                    stage.phases.len(),
                    1,
                    "the open-ended stage of `{}` is more than one hold",
                    technique.slug
                );
                assert_eq!(stage.phases[0].kind, PhaseKind::HoldOut);
                assert_eq!(stage.cycles, 1, "an open-ended stage repeats nothing");

                let before = technique.stages[..ordinal]
                    .last()
                    .and_then(|stage| stage.phases.last())
                    .map(|phase| phase.kind);
                assert_eq!(
                    before,
                    Some(PhaseKind::Exhale),
                    "the retention in `{}` is entered on nothing",
                    technique.slug
                );

                let after = technique
                    .stages
                    .get(ordinal + 1)
                    .and_then(|stage| stage.phases.first())
                    .map(|phase| phase.kind);
                assert_eq!(
                    after,
                    Some(PhaseKind::Inhale),
                    "the retention in `{}` is never breathed out of",
                    technique.slug
                );
            }
        }

        let wim_hof = TECHNIQUES
            .iter()
            .find(|technique| technique.slug == WIM_HOF)
            .expect("the catalogue contains the Wim Hof-style rounds");

        assert!(
            wim_hof.stages.iter().any(|stage| stage.open_ended),
            "the retention lost its open-ended flag"
        );
    }

    /// The strongest safety framing in the app belongs to the two techniques
    /// that can make someone faint. Losing it to a copy edit is the regression
    /// here, and it is the reason these phrases are pinned rather than the
    /// sentences: the wording may be improved, the hazards may not disappear.
    ///
    /// The list is asserted in both directions. A missing note is a warning lost
    /// at the moment of risk; an extra one is a session interrupted by advice
    /// the consent screen already gave, which is the drift that put a caution on
    /// every screen in the first place.
    #[test]
    fn the_contraindicated_techniques_carry_their_warnings() {
        let carry_a_note: Vec<_> = TECHNIQUES
            .iter()
            .filter(|technique| !technique.safety_note.is_empty())
            .map(|technique| technique.slug)
            .collect();
        assert_eq!(carry_a_note, vec!["bellows-breath", WIM_HOF]);

        for slug in [WIM_HOF, "bellows-breath"] {
            let technique = TECHNIQUES
                .iter()
                .find(|technique| technique.slug == slug)
                .unwrap_or_else(|| panic!("the catalogue contains `{slug}`"));

            for phrase in ["water", "driv"] {
                assert!(
                    technique.safety_note.contains(phrase),
                    "`{slug}` no longer warns about `{phrase}`"
                );
            }
        }
    }

    /// The occasion a slug names.
    fn occasion(slug: &str) -> &'static OccasionSeed {
        OCCASIONS
            .iter()
            .find(|occasion| occasion.slug == slug)
            .unwrap_or_else(|| panic!("the working set holds `{slug}`"))
    }

    /// What each occasion resolves to, pinned end to end.
    ///
    /// The copy above these fields is a draft TIM-28 will rewrite; the
    /// resolutions are the decision (TIM-60, D1) and this is what says so. A
    /// route that quietly moves to another technique, borrows another goal, or
    /// changes how loudly it runs is a different product answer wearing the
    /// same name, and nothing else in the tree would notice.
    #[test]
    fn the_seeded_occasions_resolve_as_decided() {
        let resolved: Vec<_> = OCCASIONS
            .iter()
            .map(|occasion| {
                (
                    occasion.slug,
                    occasion.technique_slug,
                    occasion.goal,
                    occasion.surface,
                    occasion.duration_ms,
                )
            })
            .collect();

        assert_eq!(
            resolved,
            vec![
                (
                    "before-a-presentation",
                    "box-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    180_000
                ),
                (
                    "after-a-hard-meeting",
                    "coherent-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    300_000
                ),
                (
                    "through-this-meeting",
                    "coherent-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::Discreet,
                    300_000
                ),
                (
                    "after-a-workout",
                    "extended-exhale",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    180_000
                ),
                (
                    "winding-down",
                    "extended-exhale",
                    TechniqueGoal::Sleep,
                    DeliverySurface::FullScreen,
                    300_000
                ),
                (
                    "a-moment-to-reset",
                    "physiological-sigh",
                    TechniqueGoal::Reset,
                    DeliverySurface::FullScreen,
                    60_000
                ),
            ]
        );
    }

    /// The surface is what makes an occasion more than a second name for a
    /// goal, and this pair is the whole of the argument: the same technique, at
    /// the same pace, for the same length of time, differing only in whether
    /// anybody in the room could tell. Collapsing it — by re-pointing one entry
    /// or by giving the two different doses — takes the mechanism out while
    /// leaving both entries on screen.
    #[test]
    fn the_meeting_pair_differs_only_in_its_surface() {
        let through = occasion("through-this-meeting");
        let after = occasion("after-a-hard-meeting");

        assert_eq!(through.technique_slug, after.technique_slug);
        assert_eq!(through.goal, after.goal);
        assert_eq!(through.duration_ms, after.duration_ms);
        assert_eq!(through.surface, DeliverySurface::Discreet);
        assert_eq!(after.surface, DeliverySurface::FullScreen);
    }

    /// The other half of that argument, and the reason `goal` sits on the
    /// occasion rather than being read back off the technique it routes to.
    ///
    /// Every other entry borrows the goal its technique already has, so the
    /// denormalisation has never once mattered — delete the column and nothing
    /// would look wrong. This one is what it is for: extended exhale is grouped
    /// under sleep, and coming down from a workout is not going to bed. Re-point
    /// this goal at the technique's own and the entry still reads sensibly while
    /// wearing the wrong accent everywhere it is drawn.
    #[test]
    fn the_workout_occasion_borrows_a_goal_its_technique_does_not_have() {
        let workout = occasion("after-a-workout");
        let technique = TECHNIQUES
            .iter()
            .find(|technique| technique.slug == workout.technique_slug)
            .expect("the catalogue holds the technique the workout occasion routes to");

        assert_eq!(workout.goal, TechniqueGoal::Calm);
        assert_ne!(workout.goal, technique.goal);
    }

    /// Both route tables carry a foreign key onto `techniques.slug`, so a typo
    /// fails the seed rather than reaching a client — but it fails it with a
    /// constraint name at the far end of a `mise run migrate`. This names the
    /// entry, with no database in reach.
    #[test]
    fn every_route_ends_in_a_technique_the_catalogue_holds() {
        let routed = OCCASIONS
            .iter()
            .map(|occasion| occasion.technique_slug)
            .chain(PROGRESSION.iter().map(|step| step.technique_slug));

        for slug in routed {
            assert!(
                TECHNIQUES.iter().any(|technique| technique.slug == slug),
                "a route points at `{slug}`, which the catalogue does not hold"
            );
        }
    }

    /// The progression is an ordering over *part* of the catalogue, which is
    /// the shape "suggestive, never gating" takes in data (TIM-60, D2): a
    /// technique's absence from this list is not a lock, and a technique that
    /// appeared twice would be a loop rather than a progression. The rest of
    /// the non-gating claim is structural — nothing joins to these rows to
    /// decide what somebody may breathe.
    #[test]
    fn the_progression_orders_part_of_the_catalogue() {
        assert!(
            !PROGRESSION.is_empty(),
            "a progression with no first step is not a landing place"
        );
        assert!(
            PROGRESSION.len() < TECHNIQUES.len(),
            "a progression naming every technique is the catalogue in another order"
        );

        let mut seen = std::collections::HashSet::new();
        for step in PROGRESSION {
            assert!(
                seen.insert(step.technique_slug),
                "`{}` appears twice in the progression",
                step.technique_slug
            );
            assert!(
                !step.note.is_empty(),
                "`{}` is a step with no reason to be one",
                step.technique_slug
            );
        }
    }

    /// Same reasoning as `slugs_are_unique`: the foundations upsert is keyed on
    /// the slug, and the client and M6's assistant both cite topics by it.
    #[test]
    fn foundation_slugs_are_unique() {
        let mut seen = std::collections::HashSet::new();
        for topic in FOUNDATIONS {
            assert!(seen.insert(topic.slug), "duplicate slug `{}`", topic.slug);
            assert!(!topic.question.is_empty(), "`{}` asks nothing", topic.slug);
            assert!(!topic.answer.is_empty(), "`{}` answers nothing", topic.slug);
        }
    }
}
