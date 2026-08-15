//! Transaction ownership, transfer, recovery, and input bounds.

use super::*;

/// A `jwsRepresentation` is a string. Somebody can copy it off their own device
/// and submit it from any client under any UUID they mint, and nothing inside
/// the token names who may use it — so the binding has to come from the server.
///
/// This is money rather than principle. What önd+ buys is the language model,
/// and its allowance is counted per user per UTC day, so one shared token
/// fanning out across self-minted identities is uncapped provider spend against
/// a per-user ceiling.
#[tokio::test]
async fn a_purchase_entitles_one_identity_at_a_time() {
    let db = TestDatabase::create("entitlement_replay").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    let replayed = try_submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(replayed.status, tonic::Code::PermissionDenied as i32);

    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), OTHER_USER)
            .await
            .tier,
        pb::EntitlementTier::Free as i32
    );
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        bought,
        "the buyer keeps what they bought"
    );
}

/// The other half of the binding, and the case the original schema comment chose
/// not to bind at all for: there is no account recovery, so somebody who
/// reinstalls and reaches this app with a new identity and the same Apple ID has
/// to be able to take their purchase with them.
///
/// The transaction therefore moves rather than being refused outright — but only
/// once it has sat still for the cooldown, because a binding that moved on demand
/// would be the same fan-out taken in turns, one daily allowance at a time.
/// Backdated in the column, because there is no way to make the clock move.
#[tokio::test]
async fn a_settled_purchase_follows_its_owner_to_a_new_identity() {
    let db = TestDatabase::create("entitlement_transfer").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    sqlx::query(
        "UPDATE users SET subscription_claimed_at = now() - interval '2 days' WHERE id = $1",
    )
    .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
    .execute(&db.pool)
    .await
    .expect("the claim is backdated");

    let moved = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(moved.tier, bought.tier);
    assert_eq!(moved.expires_at, bought.expires_at);

    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "the transaction moved rather than being shared"
    );
}

/// A real `jwsRepresentation` is a few kilobytes; without a bound the only
/// ceiling is tonic's 4 MiB decode limit, and every byte under it would be
/// split, base64-decoded three times and JSON-parsed on a path with no rate
/// limit in front of it. The verifier's read count is the assertion that
/// matters: rejecting the oversized token *after* doing the work would pass a
/// test that only checked the status.
#[tokio::test]
async fn a_token_too_large_to_be_a_transaction_is_refused_unread() {
    let db = TestDatabase::create("entitlement_oversized").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![]);

    let oversized = "j".repeat(64 * 1024);
    let response = try_submit(db.app_with_verifier(verifier.clone()), USER, &oversized).await;

    assert_eq!(response.status, tonic::Code::InvalidArgument as i32);
    assert_eq!(verifier.reads(), 0, "nothing decoded it to find out");
}

/// Subscribing asks nothing about an Apple account: an identity that has only
/// ever been a UUID buys, and reads back what it bought.
///
/// The rule this replaces refused exactly this caller, on the grounds that a
/// purchase hanging off a bare UUID could not be recovered onto a new phone. The
/// second half of the test is why that was never true. The anchor under a
/// subscription is the App Store account: the new phone mints a fresh identity,
/// Restore Purchases hands the server the same signed transaction, and the
/// entitlement moves — with neither identity having ever signed in.
///
/// Both halves, in one test, because the claim is one claim. The transfer rule
/// itself, including the cooldown that bounds it, is
/// `a_settled_purchase_follows_its_owner_to_a_new_identity`'s.
#[tokio::test]
async fn an_anonymous_purchase_recovers_onto_a_new_identity() {
    let db = TestDatabase::create("entitlement_anonymous").await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(bought.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), USER).await,
        bought
    );

    // Backdated because there is no way to make the clock move: what the person
    // experiences is a purchase made some days before the phone was replaced.
    sqlx::query(
        "UPDATE users SET subscription_claimed_at = now() - interval '2 days' WHERE id = $1",
    )
    .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
    .execute(&db.pool)
    .await
    .expect("the claim is backdated");

    let restored = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(restored.tier, bought.tier);
    assert_eq!(restored.expires_at, bought.expires_at);

    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "the transaction moved rather than being shared"
    );
}
