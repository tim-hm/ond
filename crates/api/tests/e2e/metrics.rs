//! The scrape target, over a real database: the numbers on the dashboard are
//! the product of a SQL `FILTER` clause and an expiry comparison — neither of
//! which a mocked repository would exercise, and both of which are the thing
//! that can be wrong. The same suite drives gRPC through the production layer
//! stack because its outcome is invisible in the HTTP status.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use api::throttle::FORWARDED_FOR;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

use crate::harness::{
    LIST_TECHNIQUES, TestDatabase, UPDATE_PROFILE, call_grpc_web, call_grpc_web_with,
    counter_total, given_user, scrape, subscribe,
};

const ALICE: &str = "11111111-1111-4111-8111-111111111111";
const BOB: &str = "22222222-2222-4222-8222-222222222222";
const CAROL: &str = "33333333-3333-4333-8333-333333333333";

/// Native gRPC metrics sit around every place a call can end: handler success
/// and refusal, the auth and throttle middleware, and a stream that fails after
/// its first message. The HTTP response is 200 in every case, so seeing these
/// five native status labels also proves the envelope was not counted instead.
#[tokio::test]
async fn native_grpc_outcomes_reach_the_exposition() {
    let database = TestDatabase::create("metrics_grpc_outcomes").await;

    let success: crate::harness::GrpcWebResponse<pb::ListTechniquesResponse> = call_grpc_web(
        database.app(),
        LIST_TECHNIQUES,
        &pb::ListTechniquesRequest {},
    )
    .await;
    assert_eq!(success.status, tonic::Code::Ok as i32);

    let invalid: crate::harness::GrpcWebResponse<pb::UpdateProfileResponse> = call_grpc_web_with(
        database.app(),
        UPDATE_PROFILE,
        &pb::UpdateProfileRequest { profile: None },
        &[(USER_ID_HEADER, ALICE)],
    )
    .await;
    assert_eq!(invalid.status, tonic::Code::InvalidArgument as i32);

    let unauthenticated: crate::harness::GrpcWebResponse<pb::ListTechniquesResponse> =
        call_grpc_web_with(
            database.app(),
            LIST_TECHNIQUES,
            &pb::ListTechniquesRequest {},
            &[(USER_ID_HEADER, "not-a-uuid")],
        )
        .await;
    assert_eq!(unauthenticated.status, tonic::Code::Unauthenticated as i32);

    let throttled = database.app_with_stopped_throttle();
    let mut throttle_status = tonic::Code::Ok as i32;
    for suffix in 1_u128..=11 {
        let user =
            uuid::Uuid::from_u128(0x7700_0000_0000_4000_8000_0000_0000_0000 | suffix).to_string();
        let response: crate::harness::GrpcWebResponse<pb::ListTechniquesResponse> =
            call_grpc_web_with(
                throttled.clone(),
                LIST_TECHNIQUES,
                &pb::ListTechniquesRequest {},
                &[(USER_ID_HEADER, &user), (FORWARDED_FOR, "198.51.100.88")],
            )
            .await;
        throttle_status = response.status;
    }
    assert_eq!(throttle_status, tonic::Code::ResourceExhausted as i32);

    let exposition = scrape(&database).await;
    assert!(
        !exposition.contains(r#"ond_requests_total{route="grpc",status="200"}"#),
        "HTTP-200 envelopes must not duplicate native completions — {exposition}"
    );
    // Each outcome against the RPC that produced it. Pairing them rather than
    // checking the status alone is what proves the method label is resolved
    // from the path of the call being recorded, and not, say, from the last one
    // to complete — including for `Chat`, whose status arrives in trailers long
    // after the response head that carried its path.
    for (code, method) in [
        (tonic::Code::Ok, LIST_TECHNIQUES),
        (tonic::Code::InvalidArgument, UPDATE_PROFILE),
        (tonic::Code::Unauthenticated, LIST_TECHNIQUES),
        (tonic::Code::ResourceExhausted, LIST_TECHNIQUES),
    ] {
        let label = format!(
            r#"ond_grpc_requests_total{{method="{method}",status="{}"}}"#,
            code as i32
        );
        assert!(
            exposition.contains(&label),
            "missing {label} — {exposition}"
        );
    }

    // Cardinality, asserted rather than assumed: a path the contract does not
    // define must collapse rather than mint a series of its own.
    assert!(
        !exposition.contains(r#"method="/ond.v1.TechniqueService/Invented""#),
        "an undefined RPC reached the label set — {exposition}"
    );
}

/// The pool is the documented failure cliff and had no gauge, and the build was
/// knowable only to somebody holding curl.
#[tokio::test]
async fn the_pool_and_the_build_reach_the_exposition() {
    let database = TestDatabase::create("metrics_pool_and_build").await;

    let exposition = scrape(&database).await;

    assert!(
        exposition.contains(r#"ond_db_pool_connections{state="idle"}"#),
        "missing the idle pool gauge — {exposition}"
    );
    assert!(
        exposition.contains(r#"ond_db_pool_connections{state="in_use"}"#),
        "missing the in-use pool gauge — {exposition}"
    );
    // One series, always 1, carrying the commit as a label — which is what lets
    // a step in this line date a regression to the deploy that caused it.
    assert!(
        exposition.contains("ond_build_info{"),
        "missing the build info series — {exposition}"
    );
    // The zero has to be published before anything panics, or `ProcessPanicked`
    // cannot fire on the first one: a counter appearing already at 1 has no
    // earlier sample, so `increase()` reads 0 across the whole window.
    assert!(
        exposition.contains("ond_panics_total 0"),
        "the panic counter must be published at zero on a healthy process — {exposition}"
    );
}

/// The two panels the dashboard exists for, against rows that actually exist.
/// Money asserted exactly rather than "greater than zero": the arithmetic is a
/// price matched by hand against `Ond.storekit`, and a sign check would pass
/// against a stale one. The third person is unsubscribed, so the user count
/// and the subscriber count cannot be satisfied by the same number.
#[tokio::test]
async fn the_census_counts_who_is_paying_and_what_it_bills() {
    let database = TestDatabase::create("metrics_census").await;

    subscribe(&database.pool, ALICE, "PLUS").await;
    subscribe(&database.pool, BOB, "PLUS").await;
    // Somebody who has opened the app and bought nothing, which the user
    // count has to include and the subscriber count has to leave out.
    given_user(&database.pool, CAROL, "Carol").await;

    let exposition = scrape(&database).await;

    assert!(
        exposition.contains("ond_users_total 3"),
        "three rows exist, and everybody with a row counts — {exposition}"
    );
    assert!(
        exposition.contains(r#"ond_active_subscriptions{tier="PLUS"} 2"#),
        "two of them are subscribed — {exposition}"
    );
    // 0.99 + 0.99
    assert!(
        exposition.contains("ond_gross_mrr_usd 1.98"),
        "list price of two önd+ subscriptions — {exposition}"
    );
}

/// A subscription that ran out is not revenue. The comparison is
/// `subscription_until > now()`, the same one the entitlement gate makes — a
/// lapsed subscriber reads Free to the app and must read Free to the
/// dashboard, or the dashboard reports income from people the server is
/// already refusing to serve.
#[tokio::test]
async fn a_lapsed_subscription_is_neither_counted_nor_billed() {
    let database = TestDatabase::create("metrics_lapsed").await;

    subscribe(&database.pool, ALICE, "PLUS").await;
    sqlx::query(
        "UPDATE users SET subscription_until = now() - interval '1 day' WHERE id = $1::uuid",
    )
    .bind(ALICE)
    .execute(&database.pool)
    .await
    .expect("the expiry is moved into the past");

    let exposition = scrape(&database).await;

    assert!(
        exposition.contains("ond_users_total 1"),
        "the person still exists — {exposition}"
    );
    assert!(
        exposition.contains(r#"ond_active_subscriptions{tier="PLUS"} 0"#),
        "but is no longer subscribed — {exposition}"
    );
    assert!(
        exposition.contains("ond_gross_mrr_usd 0"),
        "and is worth nothing a month — {exposition}"
    );
}

/// The scrape target must not be reachable on the listener Caddy proxies.
///
/// docs/observability.md puts it on its own port precisely so that no edit to
/// the Caddyfile can expose the census. Moving the route back onto the public
/// router would satisfy every other test in this file and fail here.
#[tokio::test]
async fn the_public_router_does_not_serve_the_census() {
    let database = TestDatabase::create("metrics_not_public").await;

    let response = database
        .app()
        .oneshot(
            Request::get("/metrics")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");

    assert_ne!(
        response.status(),
        StatusCode::OK,
        "the public listener answered the scrape target"
    );
}

/// A caller nobody has seen is counted once, however many times it calls. The
/// row is written by an `ON CONFLICT DO NOTHING` insert, so "was this a new
/// person" is a question only the affected row count can answer — asked
/// wrongly, the counter tracks requests rather than arrivals. The second call
/// pins that: the identical path must move nothing.
#[tokio::test]
async fn a_caller_never_seen_before_is_counted_once() {
    let database = TestDatabase::create("metrics_identity_created").await;
    let newcomer = "44444444-4444-4444-8444-444444444444";

    let before = scrape(&database).await;
    for _ in 0..2 {
        assert_eq!(
            list_techniques(&database, newcomer).await,
            tonic::Code::Ok as i32
        );
    }
    let after = scrape(&database).await;

    assert_eq!(
        counter_total(&after, "ond_identities_created_total")
            - counter_total(&before, "ond_identities_created_total"),
        1,
        "two requests from one new id are one arrival — {after}"
    );
}

async fn list_techniques(database: &TestDatabase, user_id: &str) -> i32 {
    let response: crate::harness::GrpcWebResponse<pb::ListTechniquesResponse> = call_grpc_web_with(
        database.app(),
        LIST_TECHNIQUES,
        &pb::ListTechniquesRequest::default(),
        &[(USER_ID_HEADER, user_id)],
    )
    .await;

    response.status
}
