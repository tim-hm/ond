//! Refund finality, replay resistance, and later renewals.

use api::entitlement::{StoreEnvironment, SubscriptionTier, VerifiedTransaction};
use api::proto::ond::v1 as pb;
use chrono::{Duration, Utc};

use super::fixtures::{
    MONTH, OTHER_USER, ScriptedVerifier, USER, delete_account, given_signed_in, plus, read, refund,
    refund_period, submit, subscription_period,
};
use crate::harness::{self, TestDatabase};

/// A refund is not a sale, and the dashboard has to agree: both arms of the
/// store branch used to fall through to the same counters, so every refund
/// read as a sale on the one graph that says whether anybody is paying.
/// Asserted as a delta because the recorder is process-global — and the delta
/// is the whole claim: this event moves one counter and not the other.
#[tokio::test]
async fn a_refund_is_counted_as_a_revocation_and_not_as_a_purchase() {
    let db = TestDatabase::create("entitlement_refund_metrics").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000021")),
        ("jws-refunded", refund("2000000000000021")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let before = harness::scrape(&db).await;

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    let after = harness::scrape(&db).await;

    assert_eq!(
        harness::counter_total(&after, "ond_entitlement_purchases_total")
            - harness::counter_total(&before, "ond_entitlement_purchases_total"),
        0,
        "a refund was counted as a purchase — {after}"
    );
    assert_eq!(
        outcome(&after, "revoked") - outcome(&before, "revoked"),
        1,
        "the revocation was not counted — {after}"
    );
    assert_eq!(
        outcome(&after, "honoured") - outcome(&before, "honoured"),
        0,
        "a refund was counted as honoured — {after}"
    );
}

/// One verification outcome's counter.
fn outcome(exposition: &str, outcome: &str) -> u64 {
    harness::counter_total(
        exposition,
        &format!(r#"ond_entitlement_verifications_total{{outcome="{outcome}"}}"#),
    )
}

/// A refund revokes — and only the subscription it paid for. The transaction
/// still verifies and its expiry is in the future; the revocation date is what
/// ends the entitlement. The unrelated refund is the half that could not be
/// seen otherwise: somebody who let one subscription lapse, bought another,
/// then had the old one refunded must keep what they are still paying for.
#[tokio::test]
async fn a_refund_ends_only_the_subscription_it_paid_for() {
    let db = TestDatabase::create("entitlement_revoked").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        ("jws-other-refund", refund("2000000000000009")),
    ]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    let unrelated = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-other-refund",
    )
    .await;
    assert_eq!(unrelated, bought);

    let after_refund = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(after_refund.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(after_refund.expires_at, None);
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        after_refund
    );
}

/// A refund is final, though the transaction that paid for it still verifies
/// perfectly until its own expiry. What stops it re-granting: the revocation
/// leaves the ordering marker set to its own `signedDate`, so an earlier
/// submission loses the comparison. Reachable by an honest client — `updates`
/// and `currentEntitlements` have no ordering — and buying again must still work: the third submission.
#[tokio::test]
async fn a_refund_cannot_be_undone_by_resubmitting() {
    let db = TestDatabase::create("entitlement_refund_replay").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        ("jws-bought-again", plus("2000000000000002")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let refunded = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(refunded.tier, pb::EntitlementTier::Free as i32);

    let replayed = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(replayed.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), USER).await,
        refunded
    );

    let bought_again = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-bought-again",
    )
    .await;
    assert_eq!(bought_again.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        bought_again
    );
}

/// The same finality, through the one door that used to lead around it: every
/// defence above is state on the `users` row, and `DeleteAccount` deletes it —
/// so delete, mint a fresh UUID, resubmit the pre-refund transaction the
/// client still holds, and the refunded tier came back. `revoked_transactions`
/// is a fact about the transaction, not the person, so erasure cannot reach it.
#[tokio::test]
async fn a_refund_is_not_undone_by_deleting_the_account_and_starting_again() {
    let db = TestDatabase::create("entitlement_refund_after_delete").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let refunded = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(refunded.tier, pb::EntitlementTier::Free as i32);

    let erased = delete_account(&db, USER).await;
    assert_eq!(erased, tonic::Code::Ok as i32);

    // The fresh identity the app mints the instant a deletion returns, carrying
    // the same transaction `StoreKit` still hands it on every launch.
    let replayed = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(replayed.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), OTHER_USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "and nothing was written for a later call to read back"
    );
}

/// A refund ends the individual payment it names, not the subscription's whole
/// future.
///
/// `originalTransactionId` is stable across the lineage while each renewal has
/// its own `transactionId`, which is what makes the tombstone exact.
#[tokio::test]
async fn a_purchase_signed_after_a_refund_still_entitles() {
    let db = TestDatabase::create("entitlement_refund_then_renewal").await;
    given_signed_in(&db.pool, USER).await;
    // Built in the order they were signed, which is the order Apple issues them
    // in: bought, refunded, and then paid for again under the same lineage.
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        (
            "jws-renewed",
            subscription_period(
                "2000000000000002",
                "2000000000000001",
                SubscriptionTier::Plus,
                MONTH,
            ),
        ),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;

    let renewed = submit(db.app_with_verifier(verifier.clone()), USER, "jws-renewed").await;
    assert_eq!(renewed.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(read(db.app_with_verifier(verifier), USER).await, renewed);
}

/// A refund for an earlier period arriving late leaves the current renewal
/// alone. Both periods carry the same ownership key; only their
/// `transactionId` distinguishes the payment Apple refunded, so a
/// lineage-wide tombstone would take away time the person is still paying for.
#[tokio::test]
async fn a_late_refund_for_a_prior_period_keeps_the_current_renewal() {
    let db = TestDatabase::create("entitlement_prior_period_refund").await;
    given_signed_in(&db.pool, USER).await;

    let lineage = "2000000000000001";
    let first_purchase_at = Utc::now();
    let renewal_at = first_purchase_at + Duration::seconds(1);
    let late_refund_at = renewal_at + Duration::seconds(1);
    let expires_at = late_refund_at + MONTH;
    let verifier = ScriptedVerifier::with(vec![
        (
            "jws-prior-period",
            VerifiedTransaction {
                environment: StoreEnvironment::Production,
                transaction_id: "2000000000000001".to_owned(),
                original_transaction_id: lineage.to_owned(),
                tier: SubscriptionTier::Plus,
                expires_at,
                signed_at: first_purchase_at,
                revoked_at: None,
            },
        ),
        (
            "jws-current-renewal",
            VerifiedTransaction {
                environment: StoreEnvironment::Production,
                transaction_id: "2000000000000002".to_owned(),
                original_transaction_id: lineage.to_owned(),
                tier: SubscriptionTier::Plus,
                expires_at,
                signed_at: renewal_at,
                revoked_at: None,
            },
        ),
        (
            "jws-late-prior-refund",
            VerifiedTransaction {
                environment: StoreEnvironment::Production,
                transaction_id: "2000000000000001".to_owned(),
                original_transaction_id: lineage.to_owned(),
                tier: SubscriptionTier::Plus,
                expires_at,
                signed_at: late_refund_at,
                revoked_at: Some(late_refund_at),
            },
        ),
    ]);

    submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-prior-period",
    )
    .await;
    let current = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-current-renewal",
    )
    .await;

    let after_refund = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-late-prior-refund",
    )
    .await;
    assert_eq!(after_refund, current);
    assert_eq!(read(db.app_with_verifier(verifier), USER).await, current);
}

/// Every refunded renewal remains unusable after the account row that held it
/// has been deleted. The second refund shares its lineage with the first but
/// has a different transaction id; recording only one lineage tombstone let
/// that intervening renewal grant again under a fresh identity.
#[tokio::test]
async fn a_second_refunded_period_cannot_replay_after_account_deletion() {
    let db = TestDatabase::create("entitlement_second_refund").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;

    let lineage = "2000000000000001";
    let verifier = ScriptedVerifier::with(vec![
        ("jws-first-purchase", plus(lineage)),
        ("jws-first-refund", refund(lineage)),
        (
            "jws-second-purchase",
            subscription_period("2000000000000002", lineage, SubscriptionTier::Plus, MONTH),
        ),
        (
            "jws-second-refund",
            refund_period("2000000000000002", lineage),
        ),
        (
            "jws-third-purchase",
            subscription_period("2000000000000003", lineage, SubscriptionTier::Plus, MONTH),
        ),
    ]);

    submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-first-purchase",
    )
    .await;
    submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-first-refund",
    )
    .await;
    let renewed = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-second-purchase",
    )
    .await;
    assert_eq!(renewed.tier, pb::EntitlementTier::Plus as i32);

    let refunded_again = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-second-refund",
    )
    .await;
    assert_eq!(refunded_again.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(delete_account(&db, USER).await, tonic::Code::Ok as i32);

    let replayed = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-second-purchase",
    )
    .await;
    assert_eq!(replayed.tier, pb::EntitlementTier::Free as i32);

    let later_renewal = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-third-purchase",
    )
    .await;
    assert_eq!(later_renewal.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), OTHER_USER).await,
        later_renewal
    );
}
