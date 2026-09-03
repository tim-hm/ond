//! `ListTechniques`, `ListFoundations` and `ListRoutes`, over the wire the iOS
//! client uses.

use api::proto::ond::v1 as pb;

use crate::harness::{LIST_FOUNDATIONS, LIST_ROUTES, LIST_TECHNIQUES, TestDatabase, call_grpc_web};

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
        // Both representations cross Postgres and the service mapping. The
        // structured value drives current clients; the string remains complete
        // for clients and caches that predate it.
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
            "`{slug}` reached the client with the same copy in both fields"
        );
        let mechanism = technique.mechanism_content.as_ref().unwrap_or_else(|| {
            panic!("`{slug}` reached the client without structured mechanism copy")
        });
        assert_eq!(technique.mechanism, reading_plain_text(mechanism));

        let evidence = technique.evidence_content.as_ref().unwrap_or_else(|| {
            panic!("`{slug}` reached the client without structured evidence copy")
        });
        assert_eq!(evidence.list_style, pb::ReadingListStyle::Bullets as i32);
        assert!((2..=3).contains(&evidence.items.len()));
        assert_eq!(technique.evidence, reading_plain_text(evidence));
        // A native enum column read back through a domain enum and a proto one:
        // the seed's own test proves the catalogue is graded, and this proves
        // the grade survives the two mappings rather than arriving as the zero
        // every ungraded exercise legitimately carries.
        assert_ne!(
            technique.evidence_grade,
            pb::EvidenceGrade::Unspecified as i32,
            "`{slug}` reached the client ungraded"
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

                // Air that is not moving has no shape to hold. The other half of
                // the constraint — which manner goes with which breath — is the
                // seed's to state; what matters here is that a hold never
                // arrives carrying one.
                assert!(
                    !held || phase.manner == pb::Manner::Unspecified as i32,
                    "`{slug}` has a hold shaped {}",
                    phase.manner
                );
            }
        }
    }

    assert_cadence_survives_the_wire(&response);
    assert_known_techniques(&response);
}

/// An authored zero and an absent value are different instructions, and proto3
/// tells them apart only because the field is optional. A wire that flattened
/// one into the other would put the derived turn back into every continuous
/// rhythm in the catalogue. The sigh's sip authors both columns, and its gap
/// is a zero.
fn assert_cadence_survives_the_wire(response: &pb::ListTechniquesResponse) {
    let phase = |slug: &str, index: usize| &find(response, slug).stages[0].phases[index];

    let sip = phase("physiological-sigh", 1);
    assert_eq!(sip.turn_gap_ms, Some(0));
    assert_eq!(sip.haptic_pattern.as_deref(), Some("sip"));

    let opening = phase("box-breathing", 0);
    assert_eq!(
        (opening.turn_gap_ms, opening.haptic_pattern.as_deref()),
        (None, None),
        "box breathing's inhale authors nothing and asks the client to derive"
    );
}

/// Pin representative structured copy, passages, phases, and cycle counts.
fn assert_known_techniques(response: &pb::ListTechniquesResponse) {
    let alternate_nostril = find(response, "alternate-nostril");
    let preparation = alternate_nostril
        .preparation_content
        .as_ref()
        .expect("alternate nostril breathing has structured setup steps");
    assert_eq!(
        preparation.list_style,
        pb::ReadingListStyle::Numbered as i32
    );
    assert_eq!(
        alternate_nostril.preparation,
        reading_plain_text(preparation)
    );
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
    let box_breathing = find(response, "box-breathing");
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
    assert_eq!(find(response, "physiological-sigh").stages[0].cycles, 3);
    assert_eq!(find(response, "bellows-breath").stages[0].cycles, 20);
}

/// The three exercises a passage cannot describe, and the sentence that
/// carries what an enum case cannot. Its own test because it is a different
/// claim: the one above says the catalogue arrives, this says it arrives still
/// knowing how each breath is *done* — a manner lost anywhere between the
/// column and the frame leaves the cooling breath reading as an ordinary mouth inhale.
#[tokio::test]
async fn the_shaped_breaths_keep_their_shape_over_grpc_web() {
    let db = TestDatabase::create("shaped_breaths").await;
    let response = list_techniques(&db).await;

    for (slug, stage, ordinal, manner) in [
        ("cooling-breath", 0, 0, pb::Manner::CurledTongue),
        ("pursed-lip-breathing", 0, 1, pb::Manner::PursedLips),
        ("humming-breath", 0, 1, pb::Manner::Hum),
    ] {
        assert_eq!(
            find(&response, slug).stages[stage].phases[ordinal].manner,
            manner as i32,
            "`{slug}` lost its manner on the way to the wire"
        );
    }

    // The alternative for a tongue that will not roll. One technique rather
    // than the set, because the hop this test exists to prove is column → row →
    // proto, which one carries as well as four — and which techniques prepare
    // is the seed's decision, pinned in the seed's own tests.
    assert!(
        !find(&response, "cooling-breath").preparation.is_empty(),
        "the cooling breath arrived with nothing to prepare"
    );
    assert!(
        find(&response, "cooling-breath")
            .preparation_content
            .as_ref()
            .is_some_and(|content| content.list_style == pb::ReadingListStyle::Bullets as i32),
        "the cooling breath arrived without its structured setup points"
    );
}

/// The catalogue arrives unlocked, over the wire. One flag per row is the
/// entire difference between an app that is free and one that is mostly a
/// paywall. End to end because the one thing this catches is a `DEFAULT true`
/// put back on the column, which migration 0008 dropped specifically to
/// prevent. It catches nothing else: `false` is the proto zero, so a dropped field passes here too.
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

/// The multi-stage model exists for this technique, and every part of its
/// shape is load-bearing: the retention must arrive between the deep breath
/// and the recovery, flagged open-ended, or the client schedules a hold the
/// person should end or strands them on one that never ends. The deep breath
/// is its own stage because `open_ended` is a stage property — a breath sharing it would never end.
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
        let content = topic
            .answer_content
            .as_ref()
            .unwrap_or_else(|| panic!("`{}` has no structured answer", topic.slug));
        assert_eq!(topic.answer, reading_plain_text(content));
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

/// Every seeded occasion in the order home lists them, beside the test that
/// pins it rather than inside it: the routes outgrew what one test body may
/// spend on a list of names, and clippy's line ceiling is where that showed up.
const CURATED_ORDER: &[&str] = &[
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
];

/// Every seeded occasion, resolved end to end. The pinned pair is the decision
/// this surface exists for (TIM-60, D1): "through this meeting" and "after a
/// hard meeting" differ only by `surface`, so dropping it would put a full
/// screen up in front of somebody sitting in a meeting. The register is pinned
/// by name: a mapping collapsing all registers onto one value would still be non-zero everywhere.
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
        CURATED_ORDER,
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
/// arrive on the same call as if it did not exist. A progression that filtered
/// the catalogue would look exactly like this one from inside `ListRoutes` —
/// only reading both calls at once shows the difference, which is what this does.
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

fn reading_plain_text(content: &pb::ReadingContent) -> String {
    assert!(!content.lead.trim().is_empty(), "reading copy has no lead");

    if content.items.is_empty() {
        assert_eq!(content.list_style, pb::ReadingListStyle::Unspecified as i32);
        return content.lead.clone();
    }

    let style = pb::ReadingListStyle::try_from(content.list_style)
        .expect("reading copy carries a known list style");
    let items = content
        .items
        .iter()
        .enumerate()
        .map(|(index, item)| {
            assert!(!item.trim().is_empty(), "reading copy has an empty item");
            match style {
                pb::ReadingListStyle::Bullets => format!("• {item}"),
                pb::ReadingListStyle::Numbered => format!("{}. {item}", index + 1),
                pb::ReadingListStyle::Unspecified => panic!("reading items have no list style"),
            }
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!("{}\n\n{items}", content.lead)
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
