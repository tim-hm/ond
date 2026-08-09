//! `UserTechniqueService`, over the wire the iOS client uses.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use tonic::Code;

use crate::harness::{GrpcWebResponse, TestDatabase, call_grpc_web, call_grpc_web_with};

const LIST: &str = "/ond.v1.UserTechniqueService/ListUserTechniques";
const CREATE: &str = "/ond.v1.UserTechniqueService/CreateUserTechnique";
const UPDATE: &str = "/ond.v1.UserTechniqueService/UpdateUserTechnique";
const DELETE: &str = "/ond.v1.UserTechniqueService/DeleteUserTechnique";

/// Two stable, valid identities. Fixed rather than random so a failing test
/// leaves rows someone can go and look at.
const USER: &str = "3f2b1c4d-0000-4000-8000-000000000101";
const OTHER_USER: &str = "3f2b1c4d-0000-4000-8000-000000000102";

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

    let hold_out = limits
        .phases
        .iter()
        .find(|limit| limit.kind == pb::PhaseKind::HoldOut as i32)
        .expect("the catalogue seeds empty-lung holds in closed stages");

    assert!(
        hold_out.max_duration_ms < 60_000,
        "the open-ended retention's sixty seconds leaked into a scheduled hold's ceiling"
    );

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

/// Editing replaces the whole exercise, including a shape change — a phase
/// removed from the middle renumbers everything after it, which is the case a
/// rewrite gets right for free and a patch does not.
#[tokio::test]
async fn editing_replaces_the_whole_exercise() {
    let db = TestDatabase::create("user_technique_edit").await;

    let created = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    let mut edited = draft();
    edited.name = "Shorter".to_owned();
    edited.stages[0].phases.truncate(1);
    edited.stages[0].cycles = 4;

    let updated = update(&db, USER, &created.id, edited)
        .await
        .into_ok()
        .technique
        .expect("the update answers with the technique it stored");

    assert_eq!(updated.id, created.id, "an edit keeps its identity");
    assert_eq!(updated.name, "Shorter");
    assert_eq!(updated.stages[0].phases.len(), 1);
    assert_eq!(updated.stages[0].cycles, 4);

    let listed = list(&db, USER).await.into_ok();
    assert_eq!(listed.techniques.len(), 1, "an edit is not a second copy");
    assert_eq!(listed.techniques[0], updated);
}

/// Deleting removes it, and deleting it again succeeds.
///
/// The second half is the point: a client that retried a delete whose answer it
/// never saw must converge rather than be told about a technique the person can
/// no longer see.
#[tokio::test]
async fn deleting_is_idempotent() {
    let db = TestDatabase::create("user_technique_delete").await;

    let created = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    for _ in 0..2 {
        let deleted = call_grpc_web_with::<_, pb::DeleteUserTechniqueResponse>(
            db.app(),
            DELETE,
            &pb::DeleteUserTechniqueRequest {
                id: created.id.clone(),
            },
            &[(USER_ID_HEADER, USER)],
        )
        .await;

        assert_eq!(deleted.status, Code::Ok as i32);
    }

    assert!(list(&db, USER).await.into_ok().techniques.is_empty());
}

/// One person's exercises are not another's, on every RPC that names an id.
///
/// The whole credential is a UUID somebody generated, so the ownership predicate
/// is the only thing between two callers — and it has to be on the write paths,
/// not just the read.
#[tokio::test]
async fn one_persons_exercises_are_invisible_to_another() {
    let db = TestDatabase::create("user_technique_isolation").await;

    let mine = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    assert!(
        list(&db, OTHER_USER).await.into_ok().techniques.is_empty(),
        "somebody else's list is empty"
    );

    let stolen = update(&db, OTHER_USER, &mine.id, draft()).await;

    assert_eq!(stolen.status, Code::NotFound as i32);

    let deleted = call_grpc_web_with::<_, pb::DeleteUserTechniqueResponse>(
        db.app(),
        DELETE,
        &pb::DeleteUserTechniqueRequest { id: mine.id },
        &[(USER_ID_HEADER, OTHER_USER)],
    )
    .await;

    assert_eq!(
        deleted.status,
        Code::Ok as i32,
        "a delete stays idempotent for a stranger"
    );
    assert_eq!(
        list(&db, USER).await.into_ok().techniques.len(),
        1,
        "and it deleted nothing"
    );
}

/// There is no anonymous half of this service, unlike the catalogue's.
#[tokio::test]
async fn an_unidentified_caller_has_no_exercises_to_read() {
    let db = TestDatabase::create("user_technique_anonymous").await;

    let response =
        call_grpc_web::<_, pb::ListUserTechniquesResponse>(db.app(), LIST, &request()).await;

    assert_eq!(response.status, Code::Unauthenticated as i32);
}

/// A person's own exercises are theirs, but the number of them is this
/// database's — and the caller's whole credential is a UUID they minted.
#[tokio::test]
async fn the_number_a_person_may_keep_is_bounded() {
    let db = TestDatabase::create("user_technique_ceiling").await;

    let ceiling = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served")
        .max_techniques;

    for index in 0..ceiling {
        let mut another = draft();
        another.name = format!("Mine {index}");
        assert_eq!(
            create(&db, USER, Some(another)).await.status,
            Code::Ok as i32,
            "the {index}th exercise is still inside the ceiling"
        );
    }

    // `FailedPrecondition`, not the throttle's `ResourceExhausted`: the cap
    // must stay distinguishable from "try again in a minute".
    assert_eq!(
        create(&db, USER, Some(draft())).await.status,
        Code::FailedPrecondition as i32
    );
}

/// The ceiling holds under concurrency: with one slot left, five simultaneous
/// creates admit exactly one. The count rides inside the insert's transaction
/// behind a per-person lock, so racing creates cannot both read nineteen and
/// both land.
#[tokio::test]
async fn racing_creates_cannot_pierce_the_ceiling() {
    let db = TestDatabase::create("user_technique_race").await;

    let ceiling = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served")
        .max_techniques;

    for index in 0..ceiling - 1 {
        let mut another = draft();
        another.name = format!("Mine {index}");
        assert_eq!(
            create(&db, USER, Some(another)).await.status,
            Code::Ok as i32
        );
    }

    let contender = |index: u32| {
        let mut another = draft();
        another.name = format!("Racing {index}");
        create(&db, USER, Some(another))
    };
    let outcomes = tokio::join!(
        contender(0),
        contender(1),
        contender(2),
        contender(3),
        contender(4)
    );
    let statuses = [
        outcomes.0.status,
        outcomes.1.status,
        outcomes.2.status,
        outcomes.3.status,
        outcomes.4.status,
    ];

    let admitted = statuses
        .iter()
        .filter(|status| **status == Code::Ok as i32)
        .count();
    assert_eq!(admitted, 1, "one slot admits one create: {statuses:?}");
    for status in statuses {
        assert!(
            status == Code::Ok as i32 || status == Code::FailedPrecondition as i32,
            "a racing create is admitted or refused, never broken: {status}"
        );
    }

    let listed = list(&db, USER).await.into_ok().techniques.len();
    assert_eq!(listed, ceiling as usize);
}

/// Something plainly inside every seeded range: four seconds in, eight out, ten
/// times over. The exercise somebody who has found what works for them would
/// actually write down.
fn draft() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Long exhale, mine".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Sleep as i32,
        stages: vec![stage(
            10,
            vec![
                inhale(pb::Passage::Nose, 4000),
                exhale(pb::Passage::Nose, 8000),
            ],
        )],
        rounds: 1,
    }
}

/// Alternate-nostril breathing, composed rather than curated: in through the
/// left, out through the right, in through the right, out through the left.
///
/// The exercise the whole feature exists for. It was unbuildable before the
/// passage was on the wire — the composer could only reach a 4:6:4:6 rhythm,
/// which the catalogue already holds twice over.
fn alternate_nostril() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Nadi shodhana, mine".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Focus as i32,
        stages: vec![stage(
            9,
            vec![
                inhale(pb::Passage::LeftNostril, 4000),
                exhale(pb::Passage::RightNostril, 6000),
                inhale(pb::Passage::RightNostril, 4000),
                exhale(pb::Passage::LeftNostril, 6000),
            ],
        )],
        rounds: 1,
    }
}

fn inhale(passage: pb::Passage, duration_ms: u32) -> pb::DraftPhase {
    phase(
        pb::draft_phase::Movement::Inhale(passage as i32),
        duration_ms,
    )
}

fn exhale(passage: pb::Passage, duration_ms: u32) -> pb::DraftPhase {
    phase(
        pb::draft_phase::Movement::Exhale(passage as i32),
        duration_ms,
    )
}

/// One hold, with no lungs state on it — which of the two it becomes is the
/// server's to derive from the breath before it.
fn hold(duration_ms: u32) -> pb::DraftPhase {
    phase(pb::draft_phase::Movement::Hold(pb::Hold {}), duration_ms)
}

fn phase(movement: pb::draft_phase::Movement, duration_ms: u32) -> pb::DraftPhase {
    pb::DraftPhase {
        duration_ms,
        movement: Some(movement),
    }
}

/// Three differently-shaped stages, three times over — the user-built equivalent
/// of a staged protocol. Every stage has a distinct cycle count and phase count
/// so that a stage arriving in the wrong slot reads as a wrong number rather
/// than as a coincidence.
fn sequence() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Wake, hold, settle".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Energy as i32,
        stages: vec![
            stage(
                6,
                vec![
                    inhale(pb::Passage::Nose, 2000),
                    exhale(pb::Passage::Nose, 2000),
                ],
            ),
            stage(
                1,
                vec![
                    inhale(pb::Passage::Nose, 4000),
                    hold(8000),
                    exhale(pb::Passage::Nose, 8000),
                ],
            ),
            stage(
                4,
                vec![
                    inhale(pb::Passage::Nose, 3000),
                    exhale(pb::Passage::Nose, 6000),
                ],
            ),
        ],
        rounds: 3,
    }
}

fn stage(cycles: u32, phases: Vec<pb::DraftPhase>) -> pb::DraftStage {
    pb::DraftStage { phases, cycles }
}

/// Each stage as its cycle count and how many phases it holds — enough to tell
/// three stages apart without restating every duration.
fn shape(technique: &pb::Technique) -> Vec<(u32, usize)> {
    technique
        .stages
        .iter()
        .map(|stage| (stage.cycles, stage.phases.len()))
        .collect()
}

const fn request() -> pb::ListUserTechniquesRequest {
    pb::ListUserTechniquesRequest {}
}

async fn list(db: &TestDatabase, user: &str) -> GrpcWebResponse<pb::ListUserTechniquesResponse> {
    call_grpc_web_with(db.app(), LIST, &request(), &[(USER_ID_HEADER, user)]).await
}

async fn create(
    db: &TestDatabase,
    user: &str,
    draft: Option<pb::TechniqueDraft>,
) -> GrpcWebResponse<pb::CreateUserTechniqueResponse> {
    call_grpc_web_with(
        db.app(),
        CREATE,
        &pb::CreateUserTechniqueRequest { draft },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

async fn update(
    db: &TestDatabase,
    user: &str,
    id: &str,
    draft: pb::TechniqueDraft,
) -> GrpcWebResponse<pb::UpdateUserTechniqueResponse> {
    call_grpc_web_with(
        db.app(),
        UPDATE,
        &pb::UpdateUserTechniqueRequest {
            id: id.to_owned(),
            draft: Some(draft),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}
