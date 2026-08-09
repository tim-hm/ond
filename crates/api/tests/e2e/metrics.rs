//! The scrape target.
//!
//! Over a real database rather than a unit test, because the numbers on the
//! dashboard are the product of a SQL `FILTER` clause and an expiry comparison
//! — neither of which a mocked repository would exercise, and both of which are
//! the thing that can be wrong.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

use crate::harness::{TestDatabase, subscribe};

const ALICE: &str = "11111111-1111-4111-8111-111111111111";
const BOB: &str = "22222222-2222-4222-8222-222222222222";
const CAROL: &str = "33333333-3333-4333-8333-333333333333";

/// The two panels the dashboard exists for, against rows that actually exist.
///
/// Money asserted exactly rather than "greater than zero": the arithmetic is
/// two prices written in Rust and matched by hand against `Ond.storekit`, and a
/// test that only checked the sign would pass just as happily with the two
/// products transposed — which is the mistake worth catching, because it makes
/// the cheaper product look like the whole business.
#[tokio::test]
async fn the_census_counts_who_is_paying_and_what_it_bills() {
    let database = TestDatabase::create("metrics_census").await;

    subscribe(&database.pool, ALICE, "PLUS").await;
    subscribe(&database.pool, BOB, "COACH").await;
    subscribe(&database.pool, CAROL, "COACH").await;

    let exposition = scrape(&database).await;

    assert!(
        exposition.contains("ond_users_total 3"),
        "three rows exist, and everybody with a row counts — {exposition}"
    );
    assert!(
        exposition.contains(r#"ond_active_subscriptions{tier="PLUS"} 1"#),
        "one Plus subscription — {exposition}"
    );
    assert!(
        exposition.contains(r#"ond_active_subscriptions{tier="COACH"} 2"#),
        "two Coach subscriptions — {exposition}"
    );
    // 0.99 + 4.99 + 4.99
    assert!(
        exposition.contains("ond_gross_mrr_usd 10.97"),
        "list price of one Plus and two Coach — {exposition}"
    );
}

/// A subscription that ran out is not revenue.
///
/// The comparison is `subscription_until > now()`, the same one the entitlement
/// gate makes on a single row — so a lapsed subscriber reads Free to the app
/// and must read Free to the dashboard. The two disagreeing is the specific
/// failure this suite exists to prevent, because the dashboard would then be
/// reporting income from people the server is already refusing to serve.
#[tokio::test]
async fn a_lapsed_subscription_is_neither_counted_nor_billed() {
    let database = TestDatabase::create("metrics_lapsed").await;

    subscribe(&database.pool, ALICE, "COACH").await;
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
        exposition.contains(r#"ond_active_subscriptions{tier="COACH"} 0"#),
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

async fn scrape(database: &TestDatabase) -> String {
    let response = database
        .metrics_app()
        .oneshot(
            Request::get("/metrics")
                .body(Body::empty())
                .expect("a valid request"),
        )
        .await
        .expect("the router is infallible");

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("the exposition is readable");

    String::from_utf8(body.to_vec()).expect("the exposition is text")
}
