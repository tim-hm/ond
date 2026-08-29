//! Initial purchase, resubmission, and crossgrade ordering.

use super::*;

/// The happy path, and the only one that mints an entitlement: a transaction
/// the verifier accepts becomes a tier and an expiry the next call reads back.
/// Asserted through a second RPC rather than the submission's own response,
/// because what matters is that it was *stored*.
#[tokio::test]
async fn a_verified_transaction_becomes_a_readable_entitlement() {
    let db = TestDatabase::create("entitlement_grant").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let submitted = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(submitted.tier, pb::EntitlementTier::Plus as i32);
    assert!(submitted.expires_at.is_some());

    let stored = read(db.app_with_verifier(verifier), USER).await;
    assert_eq!(stored.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(stored.expires_at, submitted.expires_at);
}

/// Somebody who has never bought anything is FREE with no date, not `NOT_FOUND`
/// and not an error. The client renders a paywall from this, so an error here
/// would make "not subscribed" indistinguishable from "the server is down" —
/// and the app is supposed to work offline.
#[tokio::test]
async fn a_caller_who_has_bought_nothing_is_free() {
    let db = TestDatabase::create("entitlement_default").await;
    let verifier = ScriptedVerifier::with(vec![]);

    let entitlement = read(db.app_with_verifier(verifier), USER).await;

    assert_eq!(entitlement.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(entitlement.expires_at, None);
}

/// The client resubmits on every launch — that is its whole retry strategy — so
/// the same token arriving repeatedly has to be one entitlement rather than an
/// error or a second grant. The expiry not moving is the assertion that matters:
/// an implementation that extended the period per submission would pass a test
/// that only checked the tier.
#[tokio::test]
async fn resubmitting_the_same_transaction_changes_nothing() {
    let db = TestDatabase::create("entitlement_idempotent").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let first = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let second = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let third = submit(db.app_with_verifier(verifier), USER, "jws-plus").await;

    assert_eq!(first, second);
    assert_eq!(second, third);
    assert_eq!(first.tier, pb::EntitlementTier::Plus as i32);
}

/// The reason the ordering key is `signedDate` and not the expiry:
/// crossgrading from the yearly plan to the monthly one issues a transaction
/// whose expiry is *earlier* than the year it replaced. Ordering by expiry
/// keeps the yearly row and leaves somebody billed monthly and entitled until
/// next year; `signedDate` takes the whole newer row, shorter expiry and all.
#[tokio::test]
async fn a_crossgrade_is_not_shadowed_by_a_longer_period() {
    let db = TestDatabase::create("entitlement_crossgrade").await;
    given_signed_in(&db.pool, USER).await;
    // Built in the order they were signed — the counter is what makes that the
    // same statement — so the monthly plan is the newer transaction despite
    // carrying the shorter period.
    let year = subscription(
        "2000000000000001",
        SubscriptionTier::Plus,
        Duration::days(365),
    );
    let month = subscription("2000000000000002", SubscriptionTier::Plus, MONTH);

    let verifier = ScriptedVerifier::with(vec![("jws-plus-year", year), ("jws-plus-month", month)]);

    let before = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-plus-year",
    )
    .await;
    let after = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-plus-month",
    )
    .await;

    assert_eq!(after.tier, pb::EntitlementTier::Plus as i32);
    assert!(
        after.expires_at.map(|at| at.seconds) < before.expires_at.map(|at| at.seconds),
        "the crossgrade's own shorter period is what the person now holds"
    );

    // And the client resubmitting the superseded yearly transaction on its next
    // launch — which it will, because `currentEntitlements` and
    // `Transaction.updates` have no ordering between them — must not put the
    // year back.
    let resubmitted = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-plus-year",
    )
    .await;
    assert_eq!(resubmitted, after);
    assert_eq!(read(db.app_with_verifier(verifier), USER).await, after);
}
