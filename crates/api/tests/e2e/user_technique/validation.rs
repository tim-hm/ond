//! Seed-derived authoring limits and phase vocabulary.

use super::*;

/// The seeded ranges bound an authored exercise, and they do it here rather than
/// only in the composer.
///
/// A client is free to render whatever dial it likes; the four-minute inhale
/// below is what a client that renders none, or one that has drifted from the
/// seed, would post. The catalogue's widest seeded inhale is ten seconds.
#[tokio::test]
async fn a_phase_outside_the_seeded_range_is_refused_by_the_server() {
    let db = TestDatabase::create("user_technique_range").await;

    let mut reckless = draft();
    reckless.stages[0].phases[0].duration_ms = 240_000;

    let refused = create(&db, USER, Some(reckless)).await;

    assert_eq!(refused.status, Code::InvalidArgument as i32);
    assert!(
        list(&db, USER).await.into_ok().techniques.is_empty(),
        "a refused draft stores nothing"
    );
}

/// The limits a composer renders from are derived from the catalogue rather
/// than declared, so this asserts against the seed's own numbers.
///
/// The retention in the Wim Hof round is a sixty-second hold, and it is
/// open-ended: the person ends it. Its range must not become the ceiling on a
/// hold somebody schedules on a clock, which is the one way this derivation
/// could quietly go wrong.
///
/// Held to `TIMED_HOLD_CEILING_MS` rather than to a loose bound below the
/// retention, because that constant is what the authoring path refuses against:
/// a derived ceiling above it would offer a person a hold the validator would
/// then reject in a fast technique, and the number it was measured against
/// would have moved without anybody choosing to move it. This is the only
/// assertion that can see the seed's numbers and the rule's at once.
#[tokio::test]
async fn the_authoring_limits_come_from_the_seeded_ranges() {
    let db = TestDatabase::create("user_technique_limits").await;

    let limits = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served even to somebody with no techniques");

    assert!(limits.max_techniques > 0);
    assert!(limits.max_stages > 0);
    assert!(limits.max_phases_per_stage > 0);
    assert!(limits.max_cycles > 0);
    assert!(limits.max_rounds > 0);
    assert!(limits.max_name_chars > 0);
    assert!(
        limits.max_summary_chars > 0,
        "a client with no ceiling to truncate against cannot offer the field"
    );

    let holds = [pb::PhaseKind::HoldIn, pb::PhaseKind::HoldOut];
    for kind in holds {
        let hold = limits
            .phases
            .iter()
            .find(|limit| limit.kind == kind as i32)
            .expect("the catalogue seeds both holds in closed stages");

        // Through `i64` because the wire carries an unsigned duration and the
        // rule states a signed one; widening both is the comparison neither
        // side can silently wrap.
        assert!(
            i64::from(hold.max_duration_ms) <= i64::from(TIMED_HOLD_CEILING_MS),
            "{kind:?} may be authored up to {}ms, past the ceiling the blackout rule holds a \
             timed hold to — either the open-ended retention leaked into the derivation, or a \
             seeded closed hold grew past a recovery beat",
            hold.max_duration_ms
        );
    }

    for limit in &limits.phases {
        assert_ne!(limit.kind, pb::PhaseKind::Unspecified as i32);
        assert!(limit.min_duration_ms > 0);
        assert!(limit.min_duration_ms <= limit.max_duration_ms);
    }
}

/// The exercise the passage exists for: alternate-nostril breathing, composed
/// by somebody rather than curated, and served back naming the same four
/// nostrils it was written with.
///
/// A round trip rather than a create alone, because the passage crosses three
/// boundaries on its way to a figure — the oneof, the column, and the assembly
/// that reads the rows back — and a drop anywhere on that path leaves a 4:6:4:6
/// rhythm that every other assertion in this file would pass.
#[tokio::test]
async fn alternate_nostril_breathing_is_authorable_and_comes_back_alternating() {
    let db = TestDatabase::create("user_technique_nostrils").await;

    create(&db, USER, Some(alternate_nostril()))
        .await
        .into_ok()
        .technique
        .expect("the nostrils are inside every seeded range");

    let listed = list(&db, USER).await.into_ok();
    let [technique] = &listed.techniques[..] else {
        panic!("one technique was stored");
    };

    assert_eq!(
        technique.stages[0]
            .phases
            .iter()
            .map(|phase| (phase.kind, phase.passage))
            .collect::<Vec<_>>(),
        vec![
            (
                pb::PhaseKind::Inhale as i32,
                pb::Passage::LeftNostril as i32
            ),
            (
                pb::PhaseKind::Exhale as i32,
                pb::Passage::RightNostril as i32
            ),
            (
                pb::PhaseKind::Inhale as i32,
                pb::Passage::RightNostril as i32
            ),
            (
                pb::PhaseKind::Exhale as i32,
                pb::Passage::LeftNostril as i32
            ),
        ]
    );
}

/// A hold has nowhere to put a passage on the wire, so what is left to check is
/// that nothing puts one there on the way out either: `PASSAGE_UNSPECIFIED` is
/// the only thing a client may read off a held breath.
#[tokio::test]
async fn a_stored_hold_names_no_passage() {
    let db = TestDatabase::create("user_technique_hold_passage").await;

    let created = create(&db, USER, Some(sequence()))
        .await
        .into_ok()
        .technique
        .expect("the sequence is stored whole");

    for stage in &created.stages {
        for phase in &stage.phases {
            let held = phase.kind == pb::PhaseKind::HoldIn as i32
                || phase.kind == pb::PhaseKind::HoldOut as i32;
            assert_eq!(
                held,
                phase.passage == pb::Passage::Unspecified as i32,
                "a phase of kind {} answered passage {}",
                phase.kind,
                phase.passage
            );
        }
    }
}
