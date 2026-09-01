//! The rules the curated catalogue must keep, which no type and no column can
//! state: that a route ends somewhere real, that a dose matches its exercise,
//! and that a warning sits on every entry whose hazard needs one. A wrong
//! answer here reaches a person as a session, so each rule names its entry.

use super::catalogue::{FOUNDATIONS, OCCASIONS, PROGRESSION, TECHNIQUES};
use super::types::*;

/// The only slug the client is allowed to know about by name, and the only
/// technique in the catalogue that has stages worth calling stages.
const WIM_HOF: &str = "wim-hof-rounds";

/// The bound the `turn_gap_ms` column states, checked where the export
/// cannot reach it: the export reads these constants and never opens the
/// database, so a gap outside the bound would ship to the app, which
/// refuses the whole catalogue over one.
#[test]
fn every_seeded_turn_gap_is_within_its_column_bound() {
    for technique in TECHNIQUES {
        for stage in technique.stages {
            for phase in stage.phases {
                let Some(gap) = phase.turn_gap_ms else {
                    continue;
                };
                assert!(
                    (0..=600).contains(&gap),
                    "`{}` authors a {gap} ms turn gap",
                    technique.slug
                );
            }
        }
    }
}

/// The tap the client resolves, restated here because the column takes
/// free text and the client falls back to `standard` on a name it does not
/// know. That fallback is a changed tap rather than a failure anybody
/// sees, so a typo has to cost a test instead.
#[test]
fn every_seeded_haptic_pattern_is_one_the_client_resolves() {
    for technique in TECHNIQUES {
        for stage in technique.stages {
            for phase in stage.phases {
                let Some(pattern) = phase.haptic_pattern else {
                    continue;
                };
                assert!(
                    HapticPattern::RESOLVED.contains(&pattern),
                    "`{}` authors the tap `{pattern}`",
                    technique.slug
                );
            }
        }
    }
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

/// The catalogue is free throughout. A `requires_subscription` typed into
/// one struct reads as a decision somebody made rather than the typo it is,
/// so what this pins is that no technique is singled out.
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

/// A `safety_note` is a hazard that arrives mid-breath, and the consent for
/// it lives in onboarding. [`PROGRESSION`] is the one route that asks the
/// person to decide nothing, so nothing on it may carry a note. The three
/// that do are each reached by a choice, and the phone stands the note up as
/// a full-screen warning before the countdown; the watch does not yet.
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

/// Every seeded technique opens with a lead and no more than three useful
/// points. The client falls back to the legacy text when structure is
/// absent, so the seed also keeps that derived projection complete.
#[test]
fn every_technique_opens_on_its_mechanism() {
    for technique in TECHNIQUES {
        assert_reading_content(technique.slug, technique.mechanism);
        assert!(
            technique.mechanism.items.len() <= 3,
            "`{}` needs at most three mechanism points",
            technique.slug
        );
    }
}

/// Every seeded technique keeps its candid evidence visible as a verdict
/// followed by two or three scannable findings.
#[test]
fn every_technique_names_its_evidence() {
    for technique in TECHNIQUES {
        assert_reading_content(technique.slug, technique.evidence);
        assert!(
            (2..=3).contains(&technique.evidence.items.len()),
            "`{}` needs two or three evidence points",
            technique.slug
        );
        assert_eq!(technique.evidence.list_style, ReadingListStyle::Bullets);
    }
}

fn assert_reading_content(owner: &str, content: ReadingContentSeed) {
    assert!(!content.lead.is_empty(), "`{owner}` needs a reading lead");
    assert!(
        content.items.iter().all(|item| !item.is_empty()),
        "`{owner}` carries an empty reading item"
    );
    assert_eq!(
        content.items.is_empty(),
        content.list_style == ReadingListStyle::None,
        "`{owner}` has items and list style out of step"
    );
    assert!(
        !content.plain_text().is_empty(),
        "`{owner}` has no fallback"
    );
}

/// The grade is the evidence paragraph in one word, so a catalogue that sits
/// on one rung tells a reader nothing about the row they are looking at. The
/// field is an enum of two values, so drifting to one is how it goes wrong.
#[test]
fn the_catalogue_grades_its_evidence_both_ways() {
    let moderate = TECHNIQUES
        .iter()
        .filter(|technique| technique.evidence_grade == EvidenceGrade::Moderate)
        .count();

    assert!(
        moderate > 0,
        "nothing in the catalogue is moderately evidenced"
    );
    assert!(
        moderate < TECHNIQUES.len(),
        "every technique claims moderate evidence, which no breathing catalogue can"
    );
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

/// The dose convention documented on [`TECHNIQUES`], enforced so a new
/// technique declares a band rather than inheriting one. Four bands are in
/// use: a five-minute sitting, an under-a-minute reset or fast bout,
/// `four-seven-eight`'s eight-round tradition, and `pursed-lip-breathing`'s
/// three minutes. `wim-hof-rounds` has none: the person ends its retention.
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
        ("pursed-lip-breathing", Some((150, 210))),
        ("humming-breath", Some((270, 330))),
        ("cooling-breath", Some((270, 330))),
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
/// seeded by accident strands them on a screen that never advances. The Wim
/// Hof retention is the only place it belongs, and it is one emptied-lung
/// hold. It is entered on an exhale and left on an inhale, and neither
/// breath may sit inside the stage, whose clock never ends.
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

/// The blackout rule as structure rather than prose: in a technique that
/// breathes fast anywhere in it, a timed hold long enough to be a target is
/// forbidden. The hold is either no longer than
/// [`physiology::TIMED_HOLD_CEILING_MS`], or open-ended so the person ends
/// it. `docs/product/breathing-science.md` §7 rule 9 carries the rest.
#[test]
fn no_hold_after_fast_breathing_is_a_target() {
    for technique in TECHNIQUES {
        if !breathes_fast_at_the_floor(technique, &[]) {
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

/// The shaped breaths are the three decided, asserted in both directions. A
/// manner that appears tells somebody mid-session how to breathe on a
/// technique nobody wrote that copy for; a manner that disappears reverts
/// the technique to a plain breath. The triple is pinned rather than the
/// slug, because a manner on the wrong phase reads correctly in a diff.
#[test]
fn the_breaths_that_are_shaped_are_the_three_decided() {
    let shaped: Vec<_> = TECHNIQUES
        .iter()
        .flat_map(|technique| {
            technique.stages.iter().flat_map(move |stage| {
                stage
                    .phases
                    .iter()
                    .filter_map(move |phase| phase.manner.map(|m| (technique.slug, phase.kind, m)))
            })
        })
        .collect();

    assert_eq!(
        shaped,
        vec![
            (
                "pursed-lip-breathing",
                PhaseKind::Exhale,
                Manner::PursedLips
            ),
            ("humming-breath", PhaseKind::Exhale, Manner::Hum),
            ("cooling-breath", PhaseKind::Inhale, Manner::CurledTongue),
        ]
    );
}

/// Every shaped breath also says how to make the shape. `Manner` names one
/// shape and cannot hedge, so a shaped technique with an empty preparation
/// leaves "through a curled tongue" as the only instruction anybody reads,
/// which for a large minority is one they cannot follow. The cooling breath
/// keeps its alternative for a tongue that will not roll.
#[test]
fn the_shaped_techniques_prepare_their_shape() {
    // Stated as the rule rather than as a list of the four that satisfy it
    // today: a fourteenth shaped technique with nothing to prepare should
    // fail by naming what it broke, not by diffing a list of slugs.
    for technique in TECHNIQUES {
        let shaped = technique
            .stages
            .iter()
            .any(|stage| stage.phases.iter().any(|phase| phase.manner.is_some()));
        assert!(
            !shaped || !technique.preparation.is_empty(),
            "`{}` shapes a breath and never says how to make the shape",
            technique.slug
        );
    }

    let cooling = TECHNIQUES
        .iter()
        .find(|technique| technique.slug == "cooling-breath")
        .expect("the catalogue seeds a cooling breath");
    assert!(
        cooling.preparation.plain_text().contains("teeth"),
        "the cooling breath stopped offering an alternative to the curl"
    );
}

/// Every technique with a safety note still names its own fainting hazard.
/// Phrases are pinned rather than sentences: the wording may be improved,
/// the hazards may not disappear. Asserted in both directions — a missing
/// note loses a warning at the moment of risk, and an extra one interrupts
/// a session with advice the consent screen already gave.
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

/// The cautions a route carries rather than its exercise, pinned in both
/// directions as the technique notes above are, and by phrase for the same
/// reason. A note belongs here when the hazard is the moment and not the
/// breathing, and neither exercise may collect the other's note.
/// `docs/product/breathing-science.md` §3.14 and §7 rule 3 carry the rest.
#[test]
fn the_protocols_that_need_a_warning_carry_one() {
    /// Each warned route, in seed order, and the hazards its note must
    /// still name.
    const WARNED: &[(&str, &[&str])] = &[
        ("when-youre-winded", &["doctor", "severe", "emergency"]),
        (
            "when-you-cant-get-a-satisfying-breath",
            &["doctor", "severe", "emergency"],
        ),
        ("with-your-child", &["hold", "fast"]),
    ];

    let carry_a_note: Vec<_> = OCCASIONS
        .iter()
        .filter(|occasion| !occasion.safety_note.is_empty())
        .map(|occasion| occasion.slug)
        .collect();
    assert_eq!(
        carry_a_note,
        WARNED.iter().map(|(slug, _)| *slug).collect::<Vec<_>>()
    );

    for (slug, hazards) in WARNED {
        let warned = occasion(slug);

        for hazard in *hazards {
            assert!(
                warned.safety_note.contains(hazard),
                "`{slug}` no longer warns about `{hazard}`"
            );
        }
    }

    let panic = occasion("when-panic-is-rising");
    assert!(
        panic.safety_note.is_empty(),
        "a full-screen warning is the one thing not to put in front of this route"
    );
    for instruction in ["Small, quiet breaths", "not deep"] {
        assert!(
            panic.summary.contains(instruction),
            "`when-panic-is-rising` no longer says `{instruction}`"
        );
    }
}

/// No occasion framed as anything but energy may resolve to a technique that
/// breathes fast. The constituency this protects — about one adult in ten,
/// already breathing in a symptom-generating pattern — is in
/// `docs/product/breathing-science.md` §6.7, and the fence is §7 rule 1. The
/// goal is matched rather than the wording, which is what gets rewritten.
#[test]
fn no_route_but_an_energising_one_reaches_fast_breathing() {
    for occasion in OCCASIONS {
        if occasion.goal == TechniqueGoal::Energy {
            continue;
        }

        let technique = technique(occasion.technique_slug);
        // Through the protocol's own rhythm, because a protocol is not
        // bounded by the exercise's dial: `with-your-child` runs Extended
        // Exhale at a five-second exhale, a second under the floor the
        // standalone exercise offers. Reading the technique alone would
        // wave through the one kind of route that can outrun its exercise.
        assert!(
            !breathes_fast_at_the_floor(technique, occasion.phase_durations_ms),
            "`{}` asks for {:?} and routes to `{}`, which can be breathed fast — \
                 fast breathing is reachable from an energising frame only",
            occasion.slug,
            occasion.goal,
            technique.slug
        );
    }
}

/// Whether any stage can be breathed fast at the fastest anybody can reach.
/// `rhythm_ms` is a protocol's own phase durations, positional, and empty
/// means the exercise alone; each phase takes the lower of dial floor and
/// prescription, for the reason in `docs/product/breathing-science.md` §7
/// rule 1. A stage that never breathes is not fast however short it is.
fn breathes_fast_at_the_floor(technique: &TechniqueSeed, rhythm_ms: &[i32]) -> bool {
    technique.stages.iter().any(|stage| {
        let cycle_ms: i32 = stage
            .phases
            .iter()
            .enumerate()
            .map(|(index, phase)| match rhythm_ms.get(index) {
                Some(prescribed) => phase.min_duration_ms.min(*prescribed),
                None => phase.min_duration_ms,
            })
            .sum();
        stage.phases.iter().any(|phase| phase.kind.is_breathing())
            && physiology::breathes_fast(cycle_ms)
    })
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

/// What an occasion resolves to: the route it takes, the framing it wears,
/// and the dose it asks for.
type Resolution = (
    &'static str,
    &'static str,
    TechniqueGoal,
    DeliverySurface,
    CopyRegister,
    &'static [i32],
    i32,
);

/// Every occasion's resolution, in seed order — the decision itself
/// (TIM-60, D1), kept as data beside the test that pins it.
const DECIDED: &[Resolution] = &[
    (
        "five-minutes-today",
        "cyclic-sighing",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "ten-quiet-minutes",
        "coherent-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        600_000,
    ),
    (
        "before-a-presentation",
        "box-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        180_000,
    ),
    (
        "after-a-hard-meeting",
        "coherent-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "through-this-meeting",
        "coherent-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "after-a-workout",
        "extended-exhale",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        180_000,
    ),
    (
        "when-youre-winded",
        "pursed-lip-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        120_000,
    ),
    (
        "when-you-cant-get-a-satisfying-breath",
        "extended-exhale",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "when-panic-is-rising",
        "extended-exhale",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[2500, 4500],
        180_000,
    ),
    (
        "in-a-tight-spot",
        "extended-exhale",
        TechniqueGoal::Calm,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "overloaded-and-need-quiet",
        "box-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        180_000,
    ),
    (
        "feeling-queasy",
        "coherent-breathing",
        TechniqueGoal::Calm,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        180_000,
    ),
    (
        "winding-down",
        "extended-exhale",
        TechniqueGoal::Sleep,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "awake-at-3am",
        "extended-exhale",
        TechniqueGoal::Sleep,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        300_000,
    ),
    (
        "with-your-child",
        "extended-exhale",
        TechniqueGoal::Calm,
        DeliverySurface::FullScreen,
        CopyRegister::Playful,
        &[3000, 5000],
        90_000,
    ),
    (
        "a-moment-to-reset",
        "physiological-sigh",
        TechniqueGoal::Reset,
        DeliverySurface::FullScreen,
        CopyRegister::Plain,
        &[],
        60_000,
    ),
    (
        "riding-out-a-craving",
        "extended-exhale",
        TechniqueGoal::Reset,
        DeliverySurface::Discreet,
        CopyRegister::Plain,
        &[],
        180_000,
    ),
];

/// What each occasion resolves to, pinned end to end. A route that moves to
/// another technique, borrows another goal, changes how loudly it runs, or
/// starts speaking in another register is a different product answer under
/// the same name, and nothing else in the tree would notice.
#[test]
fn the_seeded_occasions_resolve_as_decided() {
    let resolved: Vec<Resolution> = OCCASIONS
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

    assert_eq!(resolved, DECIDED);
}

/// The surface is what makes an occasion more than a second name for a goal:
/// each pair is the same technique, at the same pace, for the same time,
/// differing only in whether anybody in the room could tell. Membership is
/// [`OCCASIONS`]'s doc comment, never a search for coincidences — enrolling
/// one freezes together two doses that were curated apart.
#[test]
fn every_surface_pair_differs_only_in_its_surface() {
    /// The discreet entry and the full-screen one it is otherwise identical
    /// to, in that order.
    const PAIRS: &[(&str, &str)] = &[
        ("through-this-meeting", "after-a-hard-meeting"),
        ("awake-at-3am", "winding-down"),
    ];

    for (quiet_slug, loud_slug) in PAIRS {
        let quiet = occasion(quiet_slug);
        let loud = occasion(loud_slug);

        assert_eq!(
            quiet.technique_slug, loud.technique_slug,
            "`{quiet_slug}` and `{loud_slug}` no longer breathe the same exercise"
        );
        assert_eq!(
            quiet.goal, loud.goal,
            "`{quiet_slug}` and `{loud_slug}` no longer ask for the same thing"
        );
        assert_eq!(
            quiet.duration_ms, loud.duration_ms,
            "`{quiet_slug}` and `{loud_slug}` no longer run for the same time"
        );
        assert_eq!(
            quiet.surface,
            DeliverySurface::Discreet,
            "`{quiet_slug}` is the quiet half of its pair"
        );
        assert_eq!(
            loud.surface,
            DeliverySurface::FullScreen,
            "`{loud_slug}` is the full-screen half of its pair"
        );
    }
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

/// A playful route may only name an exercise its words can describe: breath
/// that moves, through the nose, nothing held. A hold would put "smell the
/// flower" on the one thing the child protocol's safety note tells a parent
/// not to teach. The proto scopes the playful register to nose breaths, so
/// any other passage falls back to the plain wording mid-session.
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

/// Why `goal` sits on the occasion rather than being read off the technique.
/// Extended exhale is grouped under sleep, and coming down from a workout is
/// not going to bed. On home only: `DialStop.goal` wears the occasion's and
/// the session it starts wears `technique.goal`, because `HomeView.begin(_:)`
/// hands on the technique and the dose and drops the framing (TIM-139).
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
/// appeared twice would be a loop rather than a progression.
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
fn foundations_are_canonical_and_structured() {
    const EXPECTED: &[&str] = &[
        "what-matters-most",
        "what-a-good-breath-feels-like",
        "is-a-deep-breath-the-answer",
        "why-it-works",
        "belly-or-chest",
        "nose-or-mouth",
        "how-slow",
        "fast-breathing-and-holds",
        "getting-comfortable",
        "how-long",
        "when-breathing-is-the-problem",
        "how-good-is-the-evidence",
        "why-no-scores",
    ];

    let mut seen = std::collections::HashSet::new();
    for topic in FOUNDATIONS {
        assert!(seen.insert(topic.slug), "duplicate slug `{}`", topic.slug);
        assert!(!topic.question.is_empty(), "`{}` asks nothing", topic.slug);
        assert!(!topic.answer.is_empty(), "`{}` answers nothing", topic.slug);

        assert_reading_content(topic.slug, topic.answer);
    }

    assert_eq!(
        FOUNDATIONS
            .iter()
            .map(|topic| topic.slug)
            .collect::<Vec<_>>(),
        EXPECTED
    );
}
