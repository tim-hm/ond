//! Seeds the technique catalogue, the breathing foundations, and the routes
//! into the catalogue — the occasion entries and the Start here progression.
//!
//! All of it is curated reference data, not user content. The values live in
//! `seed/catalogue.rs`; this parent module validates, exports, and reconciles
//! them into the database on every run. Editing the catalogue file and
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

/// `#[cfg(test)]` because seeding never asks the question — the constructors
/// below decide a phase's kind, and only the rules checking them care which
/// side of this line it fell. Without the gate it is dead code in the shipped
/// binary, which `check:rs` refuses.
#[cfg(test)]
impl PhaseKind {
    /// Whether air moves during this phase, which is the line every rule about
    /// phases actually draws — a passage to name, a cue to speak, a duration a
    /// safety rule cares about. Named rather than matched inline at each site,
    /// because the negated form ("everything that is not either hold") is the
    /// one a reader has to invert in their head.
    ///
    /// The same predicate as `technique::types::PhaseKind::is_breathing` on the
    /// API side, restated because `migrate` does not depend on `api`.
    const fn is_breathing(self) -> bool {
        matches!(self, Self::Inhale | Self::Exhale)
    }
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

/// Mirrors the `copy_register` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "copy_register", rename_all = "SCREAMING_SNAKE_CASE")]
enum CopyRegister {
    Plain,
    Playful,
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
    /// A row's worth: what it does and when to reach for it, short enough that
    /// they fit in a list.
    summary: &'static str,
    /// Why it works, in a paragraph, for the exercise's own screen to open on.
    ///
    /// Beside `summary` rather than a longer version of it: one is a line in a
    /// list, the other is a page's opening argument, and a list row carrying the
    /// paragraph would be nine lines tall.
    ///
    /// The shape every entry follows: the mechanism, then what that means for
    /// when to use it, with provenance — where a technique honestly has any —
    /// woven in as a sentence rather than given a slot. Two paragraphs,
    /// separated by a blank line. Every seeded technique carries one, and
    /// `every_technique_opens_on_its_mechanism` enforces it: a client handed an
    /// empty one opens the screen on the summary instead, which for a curated
    /// technique reads as the list row repeating itself.
    mechanism: &'static str,
    /// How strong the case for this exercise actually is, in one paragraph.
    ///
    /// Apart from `mechanism` for the reason the column states — and therefore
    /// never repeating it. A finding recited in both is a technique that has
    /// spent its caveat on persuasion: the mechanism is where a trial is cited
    /// to say the exercise is not folklore, and this is where the same trial is
    /// sized, so writing one means taking the claim out of the other.
    ///
    /// One paragraph, which `every_technique_names_its_evidence` enforces. Say
    /// what was shown, how big it was, and what is still missing.
    evidence: &'static str,
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
    /// a note and the rest carry none, and that division is a judgement worth
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
    /// Whether this one is behind önd+.
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
    register: CopyRegister,
    /// A protocol-owned rhythm, in the technique's phase order. Empty keeps the
    /// exercise's curated durations; populated is valid only for one closed,
    /// cyclic stage and must name every phase.
    phase_durations_ms: &'static [i32],
    /// The protocol's caution, empty where the underlying exercise says all
    /// that needs saying.
    safety_note: &'static str,
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

    replace_foundations(&mut tx).await?;

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

/// Writes the breathing foundations as the complete curated set.
///
/// No table references a foundation slug, so replacing the rows inside the
/// seed transaction preserves no identity by upserting. More importantly, it
/// makes removing or merging a topic in [`FOUNDATIONS`] remove the deployed
/// row too instead of leaving an old answer available forever.
async fn replace_foundations(tx: &mut sqlx::PgTransaction<'_>) -> Result<()> {
    sqlx::query("DELETE FROM foundation_topics")
        .execute(&mut **tx)
        .await
        .context("failed to clear the foundation topics")?;

    for (index, topic) in FOUNDATIONS.iter().enumerate() {
        sqlx::query(
            r"INSERT INTO foundation_topics (slug, question, answer, sort_order)
               VALUES ($1, $2, $3, $4)",
        )
        .bind(topic.slug)
        .bind(topic.question)
        .bind(topic.answer)
        .bind(i32::try_from(index).context("foundations are impossibly many")?)
        .execute(&mut **tx)
        .await
        .with_context(|| format!("failed to insert foundation topic `{}`", topic.slug))?;
    }

    Ok(())
}

/// Writes the occasion entries and the Start here progression, replacing both
/// wholesale.
///
/// Replaced rather than upserted, like the foundations above: nothing
/// references an occasion or a step, and neither carries a
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
                 (slug, name, summary, technique_slug, goal, surface, register, duration_ms,
                  phase_durations_ms, safety_note, sort_order)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(occasion.slug)
        .bind(occasion.name)
        .bind(occasion.summary)
        .bind(occasion.technique_slug)
        .bind(occasion.goal)
        .bind(occasion.surface)
        .bind(occasion.register)
        .bind(occasion.duration_ms)
        .bind(occasion.phase_durations_ms)
        .bind(occasion.safety_note)
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
                 (id, slug, name, summary, mechanism, evidence, safety_note, goal, sort_order,
                  recommended_rounds, requires_subscription)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
               ON CONFLICT (slug) DO UPDATE SET
                 name = EXCLUDED.name,
                 summary = EXCLUDED.summary,
                 mechanism = EXCLUDED.mechanism,
                 evidence = EXCLUDED.evidence,
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
    .bind(technique.mechanism)
    .bind(technique.evidence)
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
                    let breathing = phase.kind.is_breathing();
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
        let technique = technique("alternate-nostril");

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
    /// The three that do carry one are all reached by a decision — bellows
    /// breath and the Wim Hof rounds by choosing them off the catalogue, the
    /// children's exercise by tapping a moment that names a child — and on the
    /// phone the note stands as a full-screen warning between that choice and
    /// the countdown (`TechniqueWarningView`), accepted explicitly and
    /// silenceable per technique. The watch does not gate its own starts yet.
    /// The progression still has to stay clean: it is the one route through the
    /// app that asks nothing of the person choosing, and it should interrupt
    /// them with nothing either.
    #[test]
    fn the_progression_cannot_go_wrong() {
        for step in PROGRESSION {
            let technique = technique(step.technique_slug);

            assert!(
                technique.safety_note.is_empty(),
                "`{}` is on the progression and carries a safety note",
                technique.slug
            );
        }
    }

    /// Every seeded technique opens its screen on a written mechanism, in the
    /// two-paragraph shape the field doc asks for. The client falls back to the
    /// summary when this is empty — a graceful door for authored exercises, and
    /// a regression for curated ones, where it reads as the list row repeating
    /// itself. Asserted here, where the copy is authored, so a technique added
    /// without one fails `mise run check` on the Rust side rather than a Swift
    /// test three layers downstream of the export.
    #[test]
    fn every_technique_opens_on_its_mechanism() {
        for technique in TECHNIQUES {
            assert!(
                technique.mechanism.contains("\n\n"),
                "`{}` needs a two-paragraph mechanism",
                technique.slug
            );
        }
    }

    /// Every seeded technique says how strong the case for it is, in one
    /// paragraph.
    ///
    /// The rule runs the opposite way to the mechanism test above, and
    /// deliberately: two paragraphs there because a page needs an opening
    /// argument, one here because caveats grow by accretion until nobody reads
    /// them.
    #[test]
    fn every_technique_names_its_evidence() {
        for technique in TECHNIQUES {
            assert!(
                !technique.evidence.is_empty(),
                "`{}` claims nothing about its own evidence",
                technique.slug
            );
            assert!(
                !technique.evidence.contains("\n\n"),
                "`{}` needs a single-paragraph evidence note",
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

    /// The dose convention documented on [`TECHNIQUES`], enforced over the whole
    /// list so a new technique has to declare a band rather than inherit
    /// whichever one it happens to land in.
    ///
    /// Every entry needs a decision here, and three kinds get made: the five
    /// minutes a sitting opens on, the under-a-minute a reset or a fast bout
    /// runs for, and `four-seven-eight`'s own tradition capping it at eight
    /// rounds. `wim-hof-rounds` gets none of them — the person ends its
    /// retention, so there is no planned length to check at all.
    #[test]
    fn every_technique_runs_the_dose_it_was_given() {
        /// The band each technique's planned session must land in, in seconds,
        /// or `None` where the person ends the stage and there is nothing to
        /// measure.
        const DOSES: &[(&str, Option<(i64, i64)>)] = &[
            ("box-breathing", Some((270, 330))),
            ("coherent-breathing", Some((270, 330))),
            ("four-seven-eight", Some((120, 180))),
            ("extended-exhale", Some((270, 330))),
            ("physiological-sigh", Some((0, 90))),
            ("cyclic-sighing", Some((270, 330))),
            ("bellows-breath", Some((0, 90))),
            (WIM_HOF, None),
            ("long-box-breathing", Some((270, 330))),
            ("alternate-nostril", Some((270, 330))),
        ];

        for technique in TECHNIQUES {
            let decided = DOSES
                .iter()
                .find(|(slug, _)| *slug == technique.slug)
                .unwrap_or_else(|| panic!("`{}` has no decided dose", technique.slug));

            let Some((low, high)) = decided.1 else {
                continue;
            };
            let seconds = planned_seconds(technique);
            assert!(
                (low..=high).contains(&seconds),
                "`{}` runs {seconds}s, outside the {low}–{high}s it was given",
                technique.slug
            );
        }
    }

    /// The whole session a technique plans, in seconds — every stage's cycles
    /// at its own phase durations, which is the sum the clients compute too.
    fn planned_seconds(technique: &TechniqueSeed) -> i64 {
        technique
            .stages
            .iter()
            .map(|stage| {
                let cycle: i64 = stage.phases.iter().map(|p| i64::from(p.duration_ms)).sum();
                cycle * i64::from(stage.cycles)
            })
            .sum::<i64>()
            / 1000
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

        let wim_hof = technique(WIM_HOF);

        assert!(
            wim_hof.stages.iter().any(|stage| stage.open_ended),
            "the retention lost its open-ended flag"
        );
    }

    /// The blackout rule, as structure rather than prose: in a technique that
    /// over-breathes, a hold long enough to matter is ended by the person and
    /// never by the clock.
    ///
    /// Hyperventilation followed by a measured breath-hold is *the* documented
    /// way to faint doing this — the carbon dioxide that would make somebody
    /// breathe has been blown off, so the urge arrives after the oxygen has
    /// gone rather than before. Every technique in the catalogue is safe on
    /// this today, and every word explaining why lives in prose somebody
    /// writing the next one has no reason to read: the Wim Hof note says never
    /// push a hold to the limit, `BoltTestView` says the app runs no
    /// maximal-hold contest, and neither of them is a check. This is.
    ///
    /// What it forbids is a *target*: a clock-driven hold, in a technique that
    /// breathes fast anywhere in it, long enough that reaching the end of it is
    /// an achievement. The two escapes are the two safe designs — keep the hold
    /// no longer than [`physiology::TIMED_HOLD_CEILING_MS`], which is a recovery
    /// beat rather than a feat, or mark the stage open-ended so the person ends
    /// it whenever they like and there is nothing to reach.
    ///
    /// The numbers are `physiology`'s rather than this file's, and so is the
    /// comparison: `api` applies the same rule to what a person composes, and
    /// two copies of a safety threshold is a threshold that drifts.
    ///
    /// Not to be confused with `Stage.isFastRhythm` on the Swift side, which
    /// asks whether a phase is too short to print a count against. That is a
    /// legibility rule and this is a safety one; they measure different things
    /// and are not meant to agree.
    ///
    /// Whole technique rather than the stages after the fast one, deliberately.
    /// A technique repeats its stage list `recommended_rounds` times, so a hold
    /// seeded "before" the fast breathing follows it on every round but the
    /// first — an ordering rule would read as safety and enforce nothing.
    #[test]
    fn no_hold_after_fast_breathing_is_a_target() {
        for technique in TECHNIQUES {
            // Both halves of this rule read the dial rather than the curated
            // default, and they read the end of it that makes the technique
            // more dangerous: the fastest a stage can be breathed, against the
            // longest a hold can be held. A technique whose default is a
            // comfortable four and a half seconds but whose dial floor is one
            // and a half is a fast-breathing exercise for anybody who turns it
            // down, and asking about its default would never have said so.
            let breathes_fast = technique.stages.iter().any(|stage| {
                let cycle_ms: i32 = stage.phases.iter().map(|phase| phase.min_duration_ms).sum();
                // The whole cycle, holds included, because a hold inside the
                // repeating pattern is what makes the rate slow: one quick
                // breath every forty seconds accumulates carbon dioxide rather
                // than washing it out, which is the opposite of this hazard.
                // But a stage with no breathing in it at all is not breathing
                // fast however short it is — without this an open-ended
                // retention, or any brief hold stage, flips its whole technique
                // to fast and starts refusing safe holds elsewhere in it.
                stage.phases.iter().any(|phase| phase.kind.is_breathing())
                    && physiology::breathes_fast(cycle_ms)
            });

            if !breathes_fast {
                continue;
            }

            for (ordinal, stage) in technique.stages.iter().enumerate() {
                if stage.open_ended {
                    continue;
                }

                for phase in stage.phases {
                    if phase.kind.is_breathing() {
                        continue;
                    }

                    // The ceiling is on the dial's top rather than the default:
                    // a hold that only becomes a feat once somebody turns it up
                    // is still a feat the catalogue offered them.
                    assert!(
                        !physiology::is_a_timed_target(phase.max_duration_ms),
                        "stage {ordinal} of `{}` times a hold up to {}ms after fast breathing — \
                         hold it to {}ms or less, or let the person end it",
                        technique.slug,
                        phase.max_duration_ms,
                        physiology::TIMED_HOLD_CEILING_MS
                    );
                }
            }
        }
    }

    /// Every technique that carries a safety note still names its own hazard:
    /// fainting for the two that can cause it.
    /// Losing one to a copy edit is the regression here, and it is why these
    /// phrases are pinned rather than the sentences — the wording may be
    /// improved, the hazards may not disappear.
    ///
    /// The list is asserted in both directions. A missing note is a warning lost
    /// at the moment of risk; an extra one is a session interrupted by advice
    /// the consent screen already gave, which is the drift that put a caution on
    /// every screen in the first place.
    #[test]
    fn the_techniques_that_need_a_warning_carry_one() {
        let carry_a_note: Vec<_> = TECHNIQUES
            .iter()
            .filter(|technique| !technique.safety_note.is_empty())
            .map(|technique| technique.slug)
            .collect();
        assert_eq!(carry_a_note, vec!["bellows-breath", WIM_HOF]);

        for slug in [WIM_HOF, "bellows-breath"] {
            let technique = technique(slug);

            for phrase in ["water", "driv"] {
                assert!(
                    technique.safety_note.contains(phrase),
                    "`{slug}` no longer warns about `{phrase}`"
                );
            }
        }
    }

    /// The child caution belongs to the protocol that introduces the context,
    /// not to Extended Exhale whenever an adult starts it for themselves.
    #[test]
    fn the_child_protocol_carries_its_own_warning() {
        let children = occasion("with-your-child");
        for phrase in ["hold", "fast"] {
            assert!(
                children.safety_note.contains(phrase),
                "`with-your-child` no longer warns about `{phrase}`"
            );
        }
    }

    /// The technique a slug names.
    fn technique(slug: &str) -> &'static TechniqueSeed {
        TECHNIQUES
            .iter()
            .find(|technique| technique.slug == slug)
            .unwrap_or_else(|| panic!("the catalogue holds `{slug}`"))
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
    /// route that quietly moves to another technique, borrows another goal,
    /// changes how loudly it runs, or starts speaking in another register is a
    /// different product answer wearing the same name, and nothing else in the
    /// tree would notice.
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
                    occasion.register,
                    occasion.phase_durations_ms,
                    occasion.duration_ms,
                )
            })
            .collect();

        assert_eq!(
            resolved,
            vec![
                (
                    "five-minutes-today",
                    "cyclic-sighing",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[] as &[i32],
                    300_000
                ),
                (
                    "before-a-presentation",
                    "box-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[],
                    180_000
                ),
                (
                    "after-a-hard-meeting",
                    "coherent-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[],
                    300_000
                ),
                (
                    "through-this-meeting",
                    "coherent-breathing",
                    TechniqueGoal::Calm,
                    DeliverySurface::Discreet,
                    CopyRegister::Plain,
                    &[],
                    300_000
                ),
                (
                    "after-a-workout",
                    "extended-exhale",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[],
                    180_000
                ),
                (
                    "winding-down",
                    "extended-exhale",
                    TechniqueGoal::Sleep,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[],
                    300_000
                ),
                (
                    "with-your-child",
                    "extended-exhale",
                    TechniqueGoal::Calm,
                    DeliverySurface::FullScreen,
                    CopyRegister::Playful,
                    &[3000, 5000],
                    90_000
                ),
                (
                    "a-moment-to-reset",
                    "physiological-sigh",
                    TechniqueGoal::Reset,
                    DeliverySurface::FullScreen,
                    CopyRegister::Plain,
                    &[],
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

    /// A route can replace a rhythm only where phase order has one unambiguous
    /// meaning. The protocol is curated beside the catalogue, so a bad shape is
    /// a seed error rather than something every client should reinterpret.
    #[test]
    fn every_protocol_rhythm_fits_its_exercise() {
        for occasion in OCCASIONS
            .iter()
            .filter(|occasion| !occasion.phase_durations_ms.is_empty())
        {
            let technique = technique(occasion.technique_slug);
            assert_eq!(
                technique.stages.len(),
                1,
                "`{}` overrides a staged exercise",
                occasion.slug
            );
            let stage = &technique.stages[0];
            assert!(
                !stage.open_ended,
                "`{}` overrides an open-ended exercise",
                occasion.slug
            );
            assert_eq!(
                occasion.phase_durations_ms.len(),
                stage.phases.len(),
                "`{}` does not name every phase",
                occasion.slug
            );
            assert!(
                occasion
                    .phase_durations_ms
                    .iter()
                    .all(|duration| *duration > 0),
                "`{}` carries a non-positive phase duration",
                occasion.slug
            );
        }
    }

    /// A playfully-worded route may only name an exercise the playful words can
    /// actually describe: breath that moves, through the nose, and nothing held.
    ///
    /// Both halves are the safety property rather than the wording. Pointing the
    /// register at a technique with a hold would put "smell the flower" on a
    /// breath-hold — the one thing the child protocol's own safety note tells a
    /// parent not to teach — and the copy would read as an invitation to do
    /// it. Pointing it at a mouth or a single nostril is the quieter failure:
    /// the proto scopes the playful register to nose breaths, so anything else
    /// silently falls back to the plain wording mid-session, and a child is
    /// asked to smell a flower and then told to exhale through their mouth.
    ///
    /// Which routes are playful is pinned by
    /// [`the_seeded_occasions_resolve_as_decided`]; this is the constraint on
    /// what they may point at.
    #[test]
    fn a_playful_route_names_an_exercise_its_words_can_describe() {
        let playful = OCCASIONS
            .iter()
            .filter(|occasion| occasion.register == CopyRegister::Playful);

        for occasion in playful {
            let slug = occasion.technique_slug;

            for phase in technique(slug).stages.iter().flat_map(|stage| stage.phases) {
                assert!(
                    phase.kind.is_breathing(),
                    "`{slug}` is spoken playfully and holds the breath"
                );
                assert_eq!(
                    phase.passage,
                    Some(Passage::Nose),
                    "`{slug}` is spoken playfully and breathes somewhere the words cannot name"
                );
            }
        }
    }

    /// The other half of that argument, and the reason `goal` sits on the
    /// occasion rather than being read back off the technique it routes to.
    ///
    /// Every other entry borrows the goal its technique already has, so the
    /// denormalisation has never once mattered — delete the column and nothing
    /// would look wrong. This one is what it is for: extended exhale is grouped
    /// under sleep, and coming down from a workout is not going to bed. Re-point
    /// this goal at the technique's own and the entry still reads sensibly while
    /// wearing the wrong accent on home.
    ///
    /// On home, and only there — `DialStop.goal` wears the occasion's, while the
    /// session it starts wears `technique.goal`, because `HomeView.begin(_:)`
    /// hands on the technique and the dose and drops the framing. This entry is
    /// the first that makes those two differ, so it is also the first that can
    /// be seen to (TIM-139).
    #[test]
    fn the_workout_occasion_borrows_a_goal_its_technique_does_not_have() {
        let workout = occasion("after-a-workout");

        assert_eq!(workout.goal, TechniqueGoal::Calm);
        assert_ne!(workout.goal, technique(workout.technique_slug).goal);
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

    /// The client and the assistant cite foundations by slug, so the canonical
    /// set needs stable, unique keys even though the seed replaces it wholesale.
    #[test]
    fn foundations_are_canonical_and_concise() {
        const EXPECTED: &[&str] = &[
            "what-matters-most",
            "what-a-good-breath-feels-like",
            "why-it-works",
            "belly-or-chest",
            "nose-or-mouth",
            "how-slow",
            "fast-breathing-and-holds",
            "getting-comfortable",
            "how-long",
            "how-good-is-the-evidence",
            "why-no-scores",
        ];

        let mut seen = std::collections::HashSet::new();
        let mut page_words = 0;
        for topic in FOUNDATIONS {
            assert!(seen.insert(topic.slug), "duplicate slug `{}`", topic.slug);
            assert!(!topic.question.is_empty(), "`{}` asks nothing", topic.slug);
            assert!(!topic.answer.is_empty(), "`{}` answers nothing", topic.slug);

            let answer_words = topic.answer.split_whitespace().count();
            let budget = match topic.slug {
                "what-matters-most" => 60,
                "how-good-is-the-evidence" => 90,
                _ => 55,
            };
            assert!(
                answer_words <= budget,
                "`{}` uses {answer_words} words against a {budget}-word budget",
                topic.slug
            );

            page_words += topic.question.split_whitespace().count() + answer_words;
        }

        assert_eq!(
            FOUNDATIONS
                .iter()
                .map(|topic| topic.slug)
                .collect::<Vec<_>>(),
            EXPECTED
        );
        assert!(
            page_words <= 650,
            "the foundations page uses {page_words} words against a 650-word budget"
        );
    }
}
