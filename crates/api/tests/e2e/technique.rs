//! `ListTechniques`, `ListFoundations` and `ListRoutes`, over the wire the iOS
//! client uses.

use api::proto::ond::v1 as pb;

use crate::harness::{TestDatabase, call_grpc_web};

const LIST_TECHNIQUES: &str = "/ond.v1.TechniqueService/ListTechniques";
const LIST_FOUNDATIONS: &str = "/ond.v1.TechniqueService/ListFoundations";
const LIST_ROUTES: &str = "/ond.v1.TechniqueService/ListRoutes";

/// The bootstrap's acceptance criterion, minus the simulator: seeded rows in
/// Postgres reach a client as decoded protobuf, through the same router and the
/// same gRPC-Web framing the app uses.
#[tokio::test]
async fn the_seeded_catalogue_arrives_over_grpc_web() {
    let db = TestDatabase::create("seeded_catalogue").await;
    let response = list_techniques(&db).await;

    assert!(
        !response.techniques.is_empty(),
        "the seed populates the catalogue"
    );

    for technique in &response.techniques {
        let slug = &technique.slug;
        assert_ne!(
            technique.goal,
            pb::TechniqueGoal::Unspecified as i32,
            "`{slug}` reached the client with an unspecified goal"
        );
        // The seed's own tests already assert this copy was written. What this
        // layer adds is that two same-typed string columns survived two
        // mappings into two proto fields — where the failure is not a blank
        // one but the two crossing, which nothing upstream of the wire can see.
        assert!(
            !technique.mechanism.is_empty(),
            "`{slug}` reached the client with no mechanism"
        );
        assert!(
            !technique.evidence.is_empty(),
            "`{slug}` reached the client with no evidence note"
        );
        assert_ne!(
            technique.mechanism, technique.evidence,
            "`{slug}` reached the client with one paragraph in both fields"
        );
        assert!(!technique.stages.is_empty(), "`{slug}` has no stages");
        assert!(
            technique.recommended_rounds > 0,
            "`{slug}` recommends no rounds, which is a session with nothing to play"
        );

        for stage in &technique.stages {
            assert!(
                !stage.phases.is_empty(),
                "`{slug}` has a stage with no phases"
            );
            assert!(stage.cycles > 0, "`{slug}` has a stage playing no cycles");

            for phase in &stage.phases {
                assert_ne!(
                    phase.kind,
                    pb::PhaseKind::Unspecified as i32,
                    "`{slug}` has a phase of unspecified kind"
                );
                assert!(phase.duration_ms > 0, "`{slug}` has a zero-length phase");

                // A breath always says where the air goes and a hold never
                // does, which is what the `passage` column's `CHECK` states and
                // what a figure reads to decide which side of the midline to
                // draw on.
                let held = phase.kind == pb::PhaseKind::HoldIn as i32
                    || phase.kind == pb::PhaseKind::HoldOut as i32;
                assert_eq!(
                    held,
                    phase.passage == pb::Passage::Unspecified as i32,
                    "`{slug}` has a phase of kind {} answering passage {}",
                    phase.kind,
                    phase.passage
                );
            }
        }
    }

    // The one seeded technique whose passages are the exercise rather than a
    // detail of it. Held here rather than only in the seed's own tests, because
    // what the drawings and the session cues read is what came off the wire.
    let alternate_nostril = find(&response, "alternate-nostril");
    assert_eq!(
        alternate_nostril.stages[0]
            .phases
            .iter()
            .map(|phase| phase.passage)
            .collect::<Vec<_>>(),
        vec![
            pb::Passage::LeftNostril as i32,
            pb::Passage::RightNostril as i32,
            pb::Passage::RightNostril as i32,
            pb::Passage::LeftNostril as i32,
        ]
    );

    // Box breathing is four equal four-second beats by definition. Pinning one
    // known technique is what separates "the wire works" from "rows arrived
    // intact" — a grouping bug would still return the right number of them.
    let box_breathing = find(&response, "box-breathing");
    let [stage] = &box_breathing.stages[..] else {
        panic!("box breathing is a single stage");
    };

    assert_eq!(box_breathing.goal, pb::TechniqueGoal::Calm as i32);
    assert_eq!(
        stage
            .phases
            .iter()
            .map(|phase| (phase.kind, phase.duration_ms))
            .collect::<Vec<_>>(),
        vec![
            (pb::PhaseKind::Inhale as i32, 4000),
            (pb::PhaseKind::HoldIn as i32, 4000),
            (pb::PhaseKind::Exhale as i32, 4000),
            (pb::PhaseKind::HoldOut as i32, 4000),
        ]
    );

    // A stage's cycle count has both a proto zero value and a schema CHECK
    // sitting under it, so a service that never read it would still return a
    // plausible catalogue. Two techniques differing by an order of magnitude are
    // what prove the curated value made the trip.
    assert_eq!(find(&response, "physiological-sigh").stages[0].cycles, 3);
    assert_eq!(find(&response, "bellows-breath").stages[0].cycles, 20);
}

/// The catalogue arrives unlocked, over the wire.
///
/// Nothing else in the response would look wrong if this boolean were dropped
/// on the way out — the whole catalogue is served either way, because the
/// client's job is to invite rather than to hide. One flag per row is the
/// entire difference between an app that is free and an app that is mostly a
/// paywall, and this is the only place in the pipeline where it is visible.
///
/// Asserted end to end rather than left to `seed.rs`'s own test, which reads
/// the constant it is asserting about. The one thing this catches that the
/// constant cannot is a `DEFAULT true` put back on the column — which would
/// gate every technique added afterwards without a line of `catalogue.rs`
/// changing, and which migration 0008 dropped the default specifically to
/// prevent.
///
/// It catches nothing else, and that is worth stating: `false` is also the
/// proto zero value, so a `requires_subscription` dropped from the SELECT, the
/// mapping, or the message would pass here too. The direction that matters is
/// the one where somebody is unexpectedly charged, and that is the direction
/// this holds.
#[tokio::test]
async fn every_technique_arrives_unlocked() {
    let db = TestDatabase::create("catalogue_unlocked").await;
    let response = list_techniques(&db).await;

    assert!(!response.techniques.is_empty(), "the catalogue is empty");

    let gated: Vec<&str> = response
        .techniques
        .iter()
        .filter(|technique| technique.requires_subscription)
        .map(|technique| technique.slug.as_str())
        .collect();

    assert!(
        gated.is_empty(),
        "these arrived behind a subscription: {gated:?}"
    );
}

/// The multi-stage model exists for this technique, and every part of its shape
/// is load-bearing: the retention has to arrive between the deep breath that
/// empties the lungs and the recovery that refills them, flagged open-ended, or
/// the client either schedules a hold the person is supposed to end or strands
/// them on one that never ends. The rounds and the safety copy travel with it.
///
/// The deep breath is a stage of its own rather than a phase of the retention,
/// because `open_ended` is a property of the stage: a breath sharing it would
/// arrive as one the clock never ends.
#[tokio::test]
async fn the_wim_hof_rounds_arrive_as_ordered_stages() {
    let db = TestDatabase::create("wim_hof_stages").await;
    let response = list_techniques(&db).await;

    let wim_hof = find(&response, "wim-hof-rounds");
    let [breaths, transition, retention, recovery] = &wim_hof.stages[..] else {
        panic!(
            "the Wim Hof-style rounds are four stages, not {}",
            wim_hof.stages.len()
        );
    };

    let kinds = |stage: &pb::Stage| {
        stage
            .phases
            .iter()
            .map(|phase| phase.kind)
            .collect::<Vec<_>>()
    };

    assert_eq!(wim_hof.goal, pb::TechniqueGoal::Energy as i32);
    assert_eq!(wim_hof.recommended_rounds, 3);

    assert!(!breaths.open_ended);
    assert_eq!(breaths.cycles, 30);
    assert_eq!(
        kinds(breaths),
        vec![pb::PhaseKind::Inhale as i32, pb::PhaseKind::Exhale as i32]
    );

    assert!(!transition.open_ended);
    assert_eq!(transition.cycles, 1);
    assert_eq!(
        kinds(transition),
        vec![pb::PhaseKind::Inhale as i32, pb::PhaseKind::Exhale as i32],
        "the retention begins where this stage's exhale leaves off"
    );

    assert!(retention.open_ended, "the retention is ended by the person");
    assert_eq!(retention.cycles, 1);
    assert_eq!(kinds(retention), vec![pb::PhaseKind::HoldOut as i32]);

    assert!(!recovery.open_ended);
    assert_eq!(recovery.cycles, 1);
    assert_eq!(
        kinds(recovery),
        vec![
            pb::PhaseKind::Inhale as i32,
            pb::PhaseKind::HoldIn as i32,
            pb::PhaseKind::Exhale as i32,
        ]
    );

    // The one technique in the catalogue that can make someone faint carries the
    // strongest copy in the app, and it has to reach the session screen.
    assert!(wim_hof.safety_note.contains("water"));
    assert!(wim_hof.safety_note.contains("driv"));
    assert!(
        find(&response, "box-breathing").safety_note.is_empty(),
        "a technique with nothing to warn about carries no warning"
    );
}

/// The dials are rendered from this data, so a range that arrives collapsed to
/// zero leaves every client with a slider it cannot place a handle on. The
/// invariant holds catalogue-wide; the pinned technique proves the *curated*
/// range travelled rather than a copy of the default.
#[tokio::test]
async fn phase_dial_ranges_reach_the_client() {
    let db = TestDatabase::create("phase_dial_ranges").await;
    let response = list_techniques(&db).await;

    for technique in &response.techniques {
        for stage in &technique.stages {
            for phase in &stage.phases {
                assert!(
                    phase.min_duration_ms > 0
                        && phase.min_duration_ms <= phase.duration_ms
                        && phase.duration_ms <= phase.max_duration_ms,
                    "`{}` has a {}ms phase outside its {}–{}ms range",
                    technique.slug,
                    phase.duration_ms,
                    phase.min_duration_ms,
                    phase.max_duration_ms
                );
            }
        }
    }

    let exhale = &find(&response, "extended-exhale").stages[0].phases[1];
    assert_eq!(exhale.kind, pb::PhaseKind::Exhale as i32);
    assert_eq!(
        (
            exhale.min_duration_ms,
            exhale.duration_ms,
            exhale.max_duration_ms
        ),
        (6000, 6000, 8000),
        "the six-to-eight-second exhale is the evidence-based range, not a widened default"
    );
}

/// Public reference data on the same footing as the catalogue: no auth, no
/// pagination, curated order. The order is the assertion — these are the
/// questions in the sequence they occur to someone learning, and a service that
/// returned them by primary key would look identical until read.
#[tokio::test]
async fn the_foundations_arrive_over_grpc_web() {
    let db = TestDatabase::create("foundations").await;

    let response: pb::ListFoundationsResponse =
        call_grpc_web(db.app(), LIST_FOUNDATIONS, &pb::ListFoundationsRequest {})
            .await
            .into_ok();

    assert_eq!(
        response
            .topics
            .iter()
            .map(|topic| topic.slug.as_str())
            .collect::<Vec<_>>(),
        vec![
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
        ]
    );

    for topic in &response.topics {
        assert!(!topic.question.is_empty(), "`{}` asks nothing", topic.slug);
        assert!(!topic.answer.is_empty(), "`{}` answers nothing", topic.slug);
    }
}

/// The seed is a reconciliation, not an append-only history. A topic removed
/// from the canonical array must disappear on the next deployment even if the
/// row came from an older build.
#[tokio::test]
async fn the_foundation_seed_removes_retired_topics() {
    let db = TestDatabase::create("foundation_reconcile").await;

    sqlx::query(
        r"INSERT INTO foundation_topics (slug, question, answer, sort_order)
           VALUES ('retired-topic', 'Old question?', 'Old answer.', 99)",
    )
    .execute(&db.pool)
    .await
    .expect("the stale topic is inserted");

    migrate::seed::run(&db.pool)
        .await
        .expect("the reference seed reconciles");

    let slugs: Vec<String> =
        sqlx::query_scalar("SELECT slug FROM foundation_topics ORDER BY sort_order")
            .fetch_all(&db.pool)
            .await
            .expect("the reconciled foundations are readable");

    assert_eq!(slugs.len(), 13);
    assert!(!slugs.iter().any(|slug| slug == "retired-topic"));
}

/// `service.rs` groups phases through a `HashMap`, so nothing about the query's
/// `ORDER BY ordinal` survives into the response by accident. Inserting the
/// cycle out of order is what makes this assertion mean something — with rows
/// inserted in cycle order, an implementation that ignored `ordinal` entirely
/// would still pass.
#[tokio::test]
async fn phase_order_follows_ordinal_not_insertion_order() {
    let db = TestDatabase::create("phase_order").await;
    insert_technique(&db.pool, "order-probe", "CALM").await;
    insert_stage(&db.pool, "order-probe", 0).await;

    for (ordinal, kind, passage) in [
        (2, "EXHALE", Some("NOSE")),
        (0, "INHALE", Some("NOSE")),
        (1, "HOLD_IN", None),
    ] {
        sqlx::query(
            r"INSERT INTO technique_phases
                 (technique_id, stage_ordinal, ordinal, kind, passage, duration_ms,
                  min_duration_ms, max_duration_ms)
               VALUES ($1, 0, $2, $3::phase_kind, $4::passage, 1000, 1000, 1000)",
        )
        .bind("order-probe")
        .bind(ordinal)
        .bind(kind)
        .bind(passage)
        .execute(&db.pool)
        .await
        .expect("the fixture phase inserts");
    }

    let response = list_techniques(&db).await;
    let probe = find(&response, "order-probe");

    assert_eq!(
        probe.stages[0]
            .phases
            .iter()
            .map(|phase| phase.kind)
            .collect::<Vec<_>>(),
        vec![
            pb::PhaseKind::Inhale as i32,
            pb::PhaseKind::HoldIn as i32,
            pb::PhaseKind::Exhale as i32,
        ]
    );
}

/// A technique with no stage rows is corrupt data, and `service.rs` turns it
/// into `TechniqueError::Inconsistent`. What this pins is the rest of the path:
/// that the failure reaches the client as a non-zero `grpc-status` — the only
/// place a gRPC-Web client can see it, since the HTTP status stays 200 — rather
/// than as a quietly shortened list.
#[tokio::test]
async fn a_stageless_technique_fails_the_call_rather_than_vanishing() {
    let db = TestDatabase::create("stageless_technique").await;
    insert_technique(&db.pool, "stageless", "RESET").await;

    let response = call_grpc_web::<_, pb::ListTechniquesResponse>(
        db.app(),
        LIST_TECHNIQUES,
        &pb::ListTechniquesRequest {},
    )
    .await;

    assert_eq!(response.status, tonic::Code::Internal as i32);
    assert!(
        response.message.is_none(),
        "a failed call must not also carry a partial catalogue"
    );
}

/// Every seeded occasion, resolved end to end: the entry a person taps arrives
/// carrying a technique the catalogue holds, the goal it borrows, how loudly to
/// run it and for how long.
///
/// The pinned pair is the decision this whole surface exists for (TIM-60, D1).
/// "Through this meeting" and "after a hard meeting" are the same prescription
/// apart from the surface, so a response that dropped `surface` — or a service
/// that mapped both onto the proto zero — would still look like two sensible
/// occasions, and would put a full screen up in front of somebody sitting in a
/// meeting.
///
/// The register is pinned by name for the same reason one step further on. Every
/// route carrying a non-zero register is not enough: a mapping that collapsed
/// them all onto one value would pass that check, and the moment written to be
/// read aloud to a child would arrive speaking to an adult.
#[tokio::test]
async fn the_occasions_arrive_as_prescriptions_into_the_catalogue() {
    let db = TestDatabase::create("occasion_routes").await;
    let catalogue = list_techniques(&db).await;
    let routes = list_routes(&db).await;

    assert_eq!(
        routes
            .occasions
            .iter()
            .map(|occasion| occasion.slug.as_str())
            .collect::<Vec<_>>(),
        vec![
            "five-minutes-today",
            "ten-quiet-minutes",
            "before-a-presentation",
            "after-a-hard-meeting",
            "through-this-meeting",
            "after-a-workout",
            "when-youre-winded",
            "when-you-cant-get-a-satisfying-breath",
            "when-panic-is-rising",
            "in-a-tight-spot",
            "overloaded-and-need-quiet",
            "feeling-queasy",
            "winding-down",
            "awake-at-3am",
            "with-your-child",
            "a-moment-to-reset",
            "riding-out-a-craving",
        ],
        "the occasions arrive in curated order, not in whatever order the table returns"
    );

    for occasion in &routes.occasions {
        let slug = &occasion.slug;
        let prescription = prescription(occasion);

        assert!(!occasion.name.is_empty(), "`{slug}` is unnamed");
        assert_ne!(
            prescription.goal,
            pb::TechniqueGoal::Unspecified as i32,
            "`{slug}` borrows no goal"
        );
        assert_ne!(
            prescription.surface,
            pb::DeliverySurface::Unspecified as i32,
            "`{slug}` says nothing about how loudly it runs"
        );
        assert_ne!(
            prescription.register,
            pb::CopyRegister::Unspecified as i32,
            "`{slug}` says nothing about which words it speaks"
        );
        assert!(prescription.duration_ms > 0, "`{slug}` asks for no time");
        assert!(
            catalogue
                .techniques
                .iter()
                .any(|technique| technique.slug == prescription.technique_slug),
            "`{slug}` routes to `{}`, which the catalogue does not hold",
            prescription.technique_slug
        );
    }

    let through = prescription(occasion(&routes, "through-this-meeting"));
    let after = prescription(occasion(&routes, "after-a-hard-meeting"));

    assert_eq!(through.technique_slug, after.technique_slug);
    assert_eq!(through.goal, after.goal);
    assert_eq!(through.duration_ms, after.duration_ms);
    assert_eq!(through.surface, pb::DeliverySurface::Discreet as i32);
    assert_eq!(after.surface, pb::DeliverySurface::FullScreen as i32);

    let child = prescription(occasion(&routes, "with-your-child"));

    assert_eq!(child.register, pb::CopyRegister::Playful as i32);
    assert_eq!(child.technique_slug, "extended-exhale");
    assert_eq!(child.phase_durations_ms, [3000, 5000]);
    assert!(child.safety_note.contains("hold"));
    assert!(child.safety_note.contains("fast"));

    // The two breathlessness-shaped routes, over the wire for the same reason:
    // the red-flag triage is carried by the route rather than by the exercise
    // it borrows, so a client that dropped the occasion's note would show
    // nothing at all where the note is the point.
    let winded = prescription(occasion(&routes, "when-youre-winded"));
    let unsatisfying = prescription(occasion(&routes, "when-you-cant-get-a-satisfying-breath"));

    assert_eq!(winded.technique_slug, "pursed-lip-breathing");
    assert_eq!(unsatisfying.technique_slug, "extended-exhale");
    for (slug, triaged) in [
        ("when-youre-winded", winded),
        ("when-you-cant-get-a-satisfying-breath", unsatisfying),
    ] {
        for phrase in ["doctor", "severe", "emergency"] {
            assert!(
                triaged.safety_note.contains(phrase),
                "`{slug}` no longer warns about `{phrase}`"
            );
        }
    }
    assert!(
        catalogue
            .techniques
            .iter()
            .any(|technique| technique.slug == "pursed-lip-breathing"
                && technique.safety_note.is_empty()),
        "the triage belongs to the route, not to the exercise"
    );
    assert!(
        !catalogue
            .techniques
            .iter()
            .any(|technique| technique.slug == "breathing-together"),
        "the child protocol must not reappear as a standalone exercise"
    );
    assert_eq!(through.register, pb::CopyRegister::Plain as i32);
}

/// The Start here progression, and the half of it that is an absence: it names
/// some of the catalogue in a curated order, and the techniques it leaves out
/// arrive on the same call as if it did not exist. A progression that had begun
/// to filter the catalogue would look exactly like this one from inside
/// `ListRoutes` — the difference is only ever visible by reading both calls at
/// once, which is what this does.
#[tokio::test]
async fn the_progression_orders_the_catalogue_without_gating_it() {
    let db = TestDatabase::create("progression_order").await;
    let catalogue = list_techniques(&db).await;
    let routes = list_routes(&db).await;

    assert_eq!(
        routes
            .progression
            .iter()
            .map(|step| step.technique_slug.as_str())
            .collect::<Vec<_>>(),
        vec![
            "box-breathing",
            "physiological-sigh",
            "cyclic-sighing",
            "extended-exhale",
            "coherent-breathing",
        ],
        "the progression arrives in curated order — the first step is where a newcomer starts"
    );

    for step in &routes.progression {
        assert!(
            !step.note.is_empty(),
            "`{}` is a step with no reason to be one",
            step.technique_slug
        );
    }

    let omitted = catalogue
        .techniques
        .iter()
        .filter(|technique| {
            !routes
                .progression
                .iter()
                .any(|step| step.technique_slug == technique.slug)
        })
        .count();

    assert!(
        omitted > 0,
        "every technique in the catalogue is a step, so this call cannot show that the \
         ordering leaves the rest of the catalogue alone"
    );
}

async fn list_techniques(db: &TestDatabase) -> pb::ListTechniquesResponse {
    call_grpc_web(db.app(), LIST_TECHNIQUES, &pb::ListTechniquesRequest {})
        .await
        .into_ok()
}

async fn list_routes(db: &TestDatabase) -> pb::ListRoutesResponse {
    call_grpc_web(db.app(), LIST_ROUTES, &pb::ListRoutesRequest {})
        .await
        .into_ok()
}

fn occasion<'a>(response: &'a pb::ListRoutesResponse, slug: &str) -> &'a pb::Occasion {
    response
        .occasions
        .iter()
        .find(|occasion| occasion.slug == slug)
        .unwrap_or_else(|| panic!("the working set holds `{slug}`"))
}

/// The route an occasion resolves to. A message field, so proto3 lets it be
/// absent — and an occasion that resolves to nothing is the one thing this
/// surface must not be able to serve.
fn prescription(occasion: &pb::Occasion) -> &pb::Prescription {
    occasion
        .prescription
        .as_ref()
        .unwrap_or_else(|| panic!("`{}` arrived without a prescription", occasion.slug))
}

fn find<'a>(response: &'a pb::ListTechniquesResponse, slug: &str) -> &'a pb::Technique {
    response
        .techniques
        .iter()
        .find(|technique| technique.slug == slug)
        .unwrap_or_else(|| panic!("the catalogue contains `{slug}`"))
}

/// Fixture rows use the slug as the id: readable in a failure message, and
/// unique for the same reason the slug is.
async fn insert_technique(pool: &sqlx::PgPool, slug: &str, goal: &str) {
    sqlx::query(
        // `requires_subscription` is stated rather than defaulted because the
        // column has no default — the same reason `seed.rs` has to state it.
        r"INSERT INTO techniques
              (id, slug, name, summary, goal, sort_order, requires_subscription)
           VALUES ($1, $1, $2, '', $3::technique_goal, $4, true)",
    )
    .bind(slug)
    .bind(slug)
    .bind(goal)
    // Past the seeded catalogue, so fixtures sort last and the assertions above
    // about seeded data stay independent of them.
    .bind(1000)
    .execute(pool)
    .await
    .expect("the fixture technique inserts");
}

async fn insert_stage(pool: &sqlx::PgPool, technique_id: &str, ordinal: i32) {
    sqlx::query(
        r"INSERT INTO technique_stages (technique_id, ordinal, cycles, open_ended)
           VALUES ($1, $2, 1, false)",
    )
    .bind(technique_id)
    .bind(ordinal)
    .execute(pool)
    .await
    .expect("the fixture stage inserts");
}
