//! Authored-technique storage, synchronization, and ordering.

use super::*;

/// The acceptance criterion, minus the simulator: something composed on one
/// device is listed, whole and playable, by another device sending the same id.
///
/// "Playable" is the load-bearing word. The response is a `Technique` — the same
/// message the catalogue serves — so what this pins is that every field the
/// client's `SessionTimeline` reads off a curated technique is present on an
/// authored one, including the per-phase range the dials render from.
#[tokio::test]
async fn an_authored_exercise_syncs_to_a_second_device() {
    let db = TestDatabase::create("user_technique_sync").await;

    let created = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("a create answers with the technique it stored");

    assert!(!created.id.is_empty());
    assert_eq!(created.name, "Long exhale, mine");
    assert_eq!(created.goal, pb::TechniqueGoal::Sleep as i32);
    assert_eq!(created.recommended_rounds, 1);

    // A second call carrying the same identity is the whole of "it syncs": the
    // rows are the server's, so a device that has never seen this technique gets
    // it by asking.
    let listed = list(&db, USER).await.into_ok();
    let [technique] = &listed.techniques[..] else {
        panic!("the one authored exercise comes back");
    };

    assert_eq!(technique.id, created.id);
    assert_eq!(technique.slug, created.slug);
    assert_eq!(
        *technique, created,
        "listing and creating describe it alike"
    );

    let [stage] = &technique.stages[..] else {
        panic!("this draft has one stage");
    };
    assert_eq!(stage.cycles, 10);
    assert!(
        !stage.open_ended,
        "an authored stage is never one the person has to end"
    );
    assert_eq!(
        stage
            .phases
            .iter()
            .map(|phase| (phase.kind, phase.passage, phase.duration_ms))
            .collect::<Vec<_>>(),
        vec![
            (pb::PhaseKind::Inhale as i32, pb::Passage::Nose as i32, 4000),
            (pb::PhaseKind::Exhale as i32, pb::Passage::Nose as i32, 8000),
        ]
    );

    // Every phase arrives with a range containing its own duration, which is
    // what the client requires to render a dial at all — and what it rejects the
    // whole technique for lacking.
    for phase in &stage.phases {
        assert!(phase.min_duration_ms <= phase.duration_ms);
        assert!(phase.duration_ms <= phase.max_duration_ms);
    }
}

/// What somebody wrote their exercise for survives the round trip, is editable
/// afterwards, and comes back in the field a curated summary arrives in.
///
/// `Technique.summary` is the load-bearing assertion. Every surface that reads
/// the catalogue's sentence reads that field, so serving the authored one
/// through it is the whole of "an authored exercise reads the same way as a
/// curated one" — a parallel field would mean a second branch on every screen.
#[tokio::test]
async fn what_an_exercise_is_for_is_stored_and_editable() {
    let db = TestDatabase::create("user_technique_summary").await;

    let mut written = draft();
    written.summary = "  For the ten minutes before a difficult call.  ".to_owned();

    let created = create(&db, USER, Some(written))
        .await
        .into_ok()
        .technique
        .expect("a summary is inside the bound");

    assert_eq!(
        created.summary, "For the ten minutes before a difficult call.",
        "trimmed, and carried in the catalogue's own field"
    );
    assert_eq!(
        list(&db, USER).await.into_ok().techniques,
        vec![created.clone()],
        "listing and creating describe it alike"
    );

    // An edit is where this earns its place: the sentence is written by somebody
    // who has been practising the exercise, which is rarely the moment they
    // composed it.
    let mut reworded = draft();
    reworded.summary = "Ten slow minutes when my jaw is tight.".to_owned();
    let updated = update(&db, USER, &created.id, reworded)
        .await
        .into_ok()
        .technique
        .expect("the update answers with the technique it stored");

    assert_eq!(updated.summary, "Ten slow minutes when my jaw is tight.");

    // Clearing it is an ordinary edit rather than a refusal, and leaves the same
    // empty string an exercise that never had one carries.
    let cleared = update(&db, USER, &created.id, draft())
        .await
        .into_ok()
        .technique
        .expect("an exercise with nothing said about it is an ordinary exercise");

    assert!(cleared.summary.is_empty());
    assert_eq!(list(&db, USER).await.into_ok().techniques, vec![cleared]);
}

/// The bound is the service's as well as the schema's, so an over-long summary
/// names the field it objected to rather than becoming the opaque `internal` a
/// constraint violation would.
#[tokio::test]
async fn a_summary_past_the_bound_is_refused_by_the_server() {
    let db = TestDatabase::create("user_technique_summary_bound").await;

    let ceiling = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served")
        .max_summary_chars;

    let mut essay = draft();
    essay.summary = "e".repeat(ceiling as usize + 1);

    assert_eq!(
        create(&db, USER, Some(essay)).await.status,
        Code::InvalidArgument as i32
    );
    assert!(
        list(&db, USER).await.into_ok().techniques.is_empty(),
        "a refused draft stores nothing"
    );
}

/// A sequence comes back in the order it was composed in, and reordering it
/// reorders it.
///
/// The one thing three parallel tables can get wrong that a single row could
/// not. Stages and phases are stored as ordinals across two child tables and
/// reassembled by a grouping on the way out, so a sequence whose stages arrive
/// shuffled is an exercise that plays a different exercise — silently, because
/// every stage is individually valid.
///
/// The edit reverses the stages rather than changing them, which is what pins
/// the rewrite: `replace` deletes and re-inserts every ordinal, so a path that
/// merged instead of replacing would answer with the old order.
#[tokio::test]
async fn a_sequence_keeps_the_order_it_was_composed_in() {
    let db = TestDatabase::create("user_technique_sequence").await;

    let created = create(&db, USER, Some(sequence()))
        .await
        .into_ok()
        .technique
        .expect("a sequence is stored whole");

    assert_eq!(created.recommended_rounds, 3);
    assert_eq!(shape(&created), vec![(6, 2), (1, 3), (4, 2)]);
    assert_eq!(
        created.stages[1]
            .phases
            .iter()
            .map(|phase| (phase.kind, phase.duration_ms))
            .collect::<Vec<_>>(),
        vec![
            (pb::PhaseKind::Inhale as i32, 4000),
            // Sent as a bare `hold`; stored as a lungs-full one because the
            // phase before it is an inhale.
            (pb::PhaseKind::HoldIn as i32, 8000),
            (pb::PhaseKind::Exhale as i32, 8000),
        ],
        "the middle stage keeps its own pattern, in its own order"
    );

    let listed = list(&db, USER).await.into_ok();
    assert_eq!(
        listed.techniques,
        vec![created.clone()],
        "listing and creating describe a sequence alike"
    );

    let mut reordered = sequence();
    reordered.stages.reverse();

    let updated = update(&db, USER, &created.id, reordered)
        .await
        .into_ok()
        .technique
        .expect("the update answers with the technique it stored");

    assert_eq!(shape(&updated), vec![(4, 2), (1, 3), (6, 2)]);
    assert_eq!(
        list(&db, USER).await.into_ok().techniques,
        vec![updated],
        "and the stored order is the reordered one"
    );
}
