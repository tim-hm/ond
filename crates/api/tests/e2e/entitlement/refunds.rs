//! Refund finality, replay resistance, and later renewals.

use super::*;

/// A refund revokes — and only the subscription it paid for. The transaction
/// still verifies and its expiry is still in the future; what ends the
/// entitlement is the revocation date, and nothing else in the payload says so.
///
/// The unrelated refund is the half that could not be seen from the other:
/// somebody who let one subscription lapse, bought another, and then had the old
/// one refunded must keep what they are still paying for.
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

/// A refund is final, and the transaction that paid for it is still in the
/// client's hands.
///
/// The revoked transaction and the purchase it revokes are the *same*
/// subscription, and the purchase's payload carries no `revocationDate` — so it
/// verifies perfectly, forever, until its own expiry. What stops it re-granting
/// is that the revocation leaves the ordering marker set to its own `signedDate`
/// rather than clearing it; an earlier submission then loses the comparison it
/// would otherwise win against a null.
///
/// Reachable by an honest client, not only an attacker: `Transaction.updates`
/// and `currentEntitlements` have no ordering between them, so a single launch
/// can hand the server the refund and then the purchase.
///
/// Buying again afterwards has to still work, which is the half a fix could
/// easily break — hence the third submission.
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

/// The same finality, through the one door that used to lead around it.
///
/// Every defence in the test above is state on the `users` row: the surviving
/// binding, and the ordering marker the revocation leaves set. `DeleteAccount`
/// deletes that row. So the sequence was tap delete, let the client mint a fresh
/// UUID — which it must, and which the app does automatically — and resubmit the
/// pre-refund transaction the client still holds. Nothing held the binding,
/// nothing lost the ordering comparison, and the refunded tier came back until
/// the period Apple had already refunded expired.
///
/// Bounded, and not the point: the property the previous audit's critical was
/// fixed to establish is that a refund is final, and "final unless you delete
/// your account" is a different property. `revoked_transactions` is a fact about
/// the transaction rather than about the person, so erasure cannot reach it.
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
/// alone.
///
/// Both periods carry the same ownership key. Only their `transactionId`
/// distinguishes the payment Apple refunded, so a lineage-wide tombstone or
/// clear would incorrectly take away time the person is still paying for.
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
/// has been deleted.
///
/// The second refund shares its lineage with the first one but has a different
/// transaction id. Recording only one lineage tombstone let that intervening
/// renewal grant again under a fresh identity.
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
