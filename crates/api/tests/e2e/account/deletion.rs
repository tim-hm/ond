//! Anonymous and Apple-bound account erasure behavior.

use super::*;

/// The promise `web/privacy.html` makes, asserted table by table: a person with
/// a profile, a signed-in binding, sessions, a controlled pause, spent assistant
/// allowance and a subscription asks to be erased, and none of it survives.
///
/// Every child table is checked by name rather than trusting `ON DELETE CASCADE`
/// in the abstract. A table added later with `ON DELETE SET NULL`, or with no
/// foreign key at all, is exactly the change that would leave somebody's history
/// behind while every other assertion here still passed.
///
/// The Apple account and the App Store transaction are checked from the other
/// side — not "the column is gone", which the row's absence guarantees, but "the
/// value is claimable again". Both are `UNIQUE`, so a deletion that somehow left
/// either behind would lock the person out of ever coming back under the same
/// Apple ID or being entitled by the subscription they are still paying for.
#[tokio::test]
async fn deleting_an_account_leaves_nothing_behind() {
    let db = TestDatabase::create("account_delete").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);
    let transaction = "2000000900000001";

    given_user(&db.pool, OLD_DEVICE, "Leaving").await;
    given_session(
        &db.pool,
        OLD_DEVICE,
        "5e551011-0000-4000-8000-00000000000a",
        "breathed",
    )
    .await;
    given_bolt_score(
        &db.pool,
        OLD_DEVICE,
        "b01f0000-0000-4000-8000-00000000000a",
        37,
    )
    .await;
    given_resting_rate(
        &db.pool,
        OLD_DEVICE,
        "4a7e0000-0000-4000-8000-00000000000a",
        13,
    )
    .await;
    given_quota(&db.pool, OLD_DEVICE, 0, 4).await;
    subscribe(&db.pool, OLD_DEVICE, "PLUS").await;
    given_app_store_binding(&db.pool, OLD_DEVICE, transaction).await;
    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    let response = try_delete_account(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        "jws-apple",
    )
    .await;
    assert_eq!(response.status, tonic::Code::Ok as i32);

    assert!(!exists(&db.pool, OLD_DEVICE).await);
    assert!(sessions_of(&db.pool, OLD_DEVICE).await.is_empty());
    assert!(bolt_seconds_of(&db.pool, OLD_DEVICE).await.is_empty());
    assert!(resting_rates_of(&db.pool, OLD_DEVICE).await.is_empty());
    assert!(quota_of(&db.pool, OLD_DEVICE).await.is_empty());
    assert_eq!(holder_of_transaction(&db.pool, transaction).await, None);
    assert_eq!(
        live_credentials(&db.pool, OLD_DEVICE).await,
        0,
        "the credential that proved this identity cascaded with the row it proved"
    );

    let returning = sign_in(db.app_with_identity(verifier), NEW_DEVICE, "jws-apple").await;
    assert_eq!(
        returning.user_id, NEW_DEVICE,
        "the Apple account is free, so a later sign-in is a first one rather than a merge"
    );
}

/// A signed-in account is not erasable by whoever holds its anonymous id.
///
/// That id is the weakest credential in the system — a UUID a person is invited
/// to paste into a support email — and this is the only irreversible operation
/// in the API. Sign-in already refuses to let possession of an
/// anonymous id fold a bound row away; before this, the same id could destroy
/// that row outright, along with everything signing in was supposed to make
/// recoverable.
///
/// The successful deletion at the end is the half a refusal could easily break:
/// the credential is a gate, not a wall, and somebody who signs in must still be
/// able to leave.
#[tokio::test]
async fn erasing_an_apple_bound_account_needs_a_fresh_apple_credential() {
    let db = TestDatabase::create("account_delete_credential").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Signed in").await;
    given_session(
        &db.pool,
        OLD_DEVICE,
        "5e551011-0000-4000-8000-00000000000e",
        "kept",
    )
    .await;
    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    // The session credential is presented and the Apple one is not, so the
    // refusal is `service::delete_account`'s rather than the identity layer's —
    // which is the rule this test is about. The identity layer's own refusal is
    // `identity.rs`'s subject.
    let refused = try_delete_account(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        "",
    )
    .await;
    assert_eq!(refused.status, tonic::Code::Unauthenticated as i32);
    assert!(exists(&db.pool, OLD_DEVICE).await);
    assert_eq!(sessions_of(&db.pool, OLD_DEVICE).await.len(), 1);

    let erased = try_delete_account(
        db.app_with_identity(verifier),
        OLD_DEVICE,
        Some(&signed_in.credential),
        "jws-apple",
    )
    .await;
    assert_eq!(erased.status, tonic::Code::Ok as i32);
    assert!(!exists(&db.pool, OLD_DEVICE).await);
}

#[tokio::test]
async fn deletion_refuses_a_sign_in_challenge_and_consumes_its_own() {
    let db = TestDatabase::create("account_delete_challenge").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);
    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    let wrong_purpose = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    let refused = try_delete_with_identity_token(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        token_with_nonce("jws-apple", &wrong_purpose.nonce),
    )
    .await;
    assert_eq!(refused.status, tonic::Code::Unauthenticated as i32);
    assert!(exists(&db.pool, OLD_DEVICE).await);

    let deletion = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        pb::AppleAuthorizationPurpose::DeleteAccount,
    )
    .await
    .into_ok();
    let token = token_with_nonce("jws-apple", &deletion.nonce);
    let erased = try_delete_with_identity_token(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        Some(&signed_in.credential),
        token,
    )
    .await;
    assert_eq!(erased.status, tonic::Code::Ok as i32);

    let remaining = sqlx::query_scalar!(
        r#"SELECT count(*) AS "count!" FROM apple_authorization_challenges
            WHERE user_id = $1"#,
        uuid(OLD_DEVICE)
    )
    .fetch_one(&db.pool)
    .await
    .expect("challenges are countable");
    assert_eq!(remaining, 0);
}

/// A token Apple really signed proves an Apple account, not *this* Apple
/// account — so the `sub` has to match the binding.
///
/// Reachable by anybody with an Apple ID and somebody else's id: verification
/// alone would turn the check into a formality, since the point is not that a
/// credential exists but that it is the one this row was filed under.
///
/// `PERMISSION_DENIED` rather than `UNAUTHENTICATED`, because nothing is wrong
/// with the credential — a client that told this person their Apple ID was
/// rejected would send them to re-authenticate as the wrong account forever.
#[tokio::test]
async fn erasing_an_apple_bound_account_refuses_another_apple_account() {
    let db = TestDatabase::create("account_delete_wrong_apple").await;
    let verifier = ScriptedIdentityVerifier::with(vec![
        ("jws-apple", APPLE_ACCOUNT),
        ("jws-other", OTHER_APPLE_ACCOUNT),
    ]);

    given_user(&db.pool, OLD_DEVICE, "Signed in").await;
    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    let refused = try_delete_account(
        db.app_with_identity(verifier),
        OLD_DEVICE,
        Some(&signed_in.credential),
        "jws-other",
    )
    .await;

    assert_eq!(refused.status, tonic::Code::PermissionDenied as i32);
    assert!(exists(&db.pool, OLD_DEVICE).await);
    assert_eq!(
        apple_account_of(&db.pool, OLD_DEVICE).await.as_deref(),
        Some(APPLE_ACCOUNT),
        "a refused erasure changes nothing about the binding it failed to prove"
    );
}

/// A sign-in that lands between the credential being weighed and the row being
/// deleted does not lose the account it just bound.
///
/// The two halves of the decision cannot be one statement: the server reads the
/// binding, then verifies a token *with Apple*, which is a network round trip no
/// transaction may be held across. So the erasure re-reads the binding under a
/// lock and refuses if it has changed — otherwise a caller holding only the
/// anonymous id could send a credential-free deletion, race a sign-in, and erase
/// an Apple-bound account by arriving second.
///
/// Driven here by binding the row *while* the deletion is in flight, which is
/// what the sleep buys: the identity verifier that erasure consults is the same
/// one this suite scripts, so the ordering is the server's rather than the
/// test's.
#[tokio::test]
async fn a_sign_in_racing_an_erasure_is_not_erased_without_its_credential() {
    let db = TestDatabase::create("account_delete_race").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Signing in").await;

    // The row is anonymous when the erasure reads it, and bound by the time the
    // `DELETE` would run — the state a client with only the id could arrange by
    // sending both at once.
    let mut binding = db.pool.begin().await.expect("a second transaction");
    sqlx::query!(
        "UPDATE users SET apple_user_id = $2 WHERE id = $1",
        uuid(OLD_DEVICE),
        APPLE_ACCOUNT
    )
    .execute(&mut *binding)
    .await
    .expect("the sign-in binds the row");

    let app = db.app_with_identity(verifier);
    let erasing = tokio::spawn(async move { delete_account(app, OLD_DEVICE).await });

    tokio::time::sleep(Duration::from_millis(250)).await;
    binding.commit().await.expect("the sign-in lands");

    let refused = erasing.await.expect("the erasure finished");
    assert_eq!(refused.status, tonic::Code::Unauthenticated as i32);
    assert!(
        exists(&db.pool, OLD_DEVICE).await,
        "the account the sign-in had just bound is still there"
    );
}

/// The other side of the same rule: an identity with no Apple account attached
/// is erased on the header alone, whatever the request carries.
///
/// The majority of people never sign in, and the header genuinely is the whole
/// of their claim — there is no stronger credential to ask them for, so
/// demanding one would put erasure out of reach of most of the people entitled
/// to it. The token here is not merely absent but *unverifiable*, which is what
/// pins that an anonymous erasure never reaches the verifier at all.
#[tokio::test]
async fn erasing_an_anonymous_account_needs_nothing_but_the_header() {
    let db = TestDatabase::create("account_delete_anonymous").await;

    given_user(&db.pool, OLD_DEVICE, "Local only").await;

    let erased = try_delete_account(
        db.app_with_identity(ScriptedIdentityVerifier::refusing()),
        OLD_DEVICE,
        None,
        "forged",
    )
    .await;

    assert_eq!(erased.status, tonic::Code::Ok as i32);
    assert!(!exists(&db.pool, OLD_DEVICE).await);
}

/// Scoped to the caller, which is the whole of the authorisation on this RPC:
/// the request carries no id, so the only person it can name is the one in the
/// header.
#[tokio::test]
async fn deleting_an_account_leaves_everybody_else_alone() {
    let db = TestDatabase::create("account_delete_scope").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Staying").await;
    given_session(
        &db.pool,
        OLD_DEVICE,
        "5e551011-0000-4000-8000-00000000000b",
        "kept",
    )
    .await;
    given_user(&db.pool, NEW_DEVICE, "Leaving").await;
    given_session(
        &db.pool,
        NEW_DEVICE,
        "5e551011-0000-4000-8000-00000000000c",
        "erased",
    )
    .await;

    delete_account(db.app_with_identity(verifier), NEW_DEVICE).await;

    assert!(!exists(&db.pool, NEW_DEVICE).await);
    assert_eq!(sessions_of(&db.pool, OLD_DEVICE).await.len(), 1);
}

/// The reason the client mints a fresh identity the instant this returns, pinned
/// on the server side where the behaviour actually lives.
///
/// `identity::resolve` upserts a row for any well-formed id it holds no merge
/// tombstone for — and an erasure writes none, deliberately — so a single later
/// request on the old id
/// brings the row back — empty, unreachable from any Apple account, and
/// belonging to somebody who asked to be forgotten. There is no server-side
/// defence to add without keeping a record of every id ever erased, which is the
/// opposite of what was asked for.
#[tokio::test]
async fn a_request_on_an_erased_identity_recreates_it_empty() {
    let db = TestDatabase::create("account_delete_resurrect").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Leaving").await;
    given_session(
        &db.pool,
        OLD_DEVICE,
        "5e551011-0000-4000-8000-00000000000d",
        "erased",
    )
    .await;

    delete_account(db.app_with_identity(verifier.clone()), OLD_DEVICE).await;
    assert!(!exists(&db.pool, OLD_DEVICE).await);

    // The catalogue: the most innocent request there is, and identified, which
    // is all it takes.
    let listed: GrpcWebResponse<pb::ListTechniquesResponse> = call_grpc_web_with(
        db.app_with_identity(verifier),
        "/ond.v1.TechniqueService/ListTechniques",
        &pb::ListTechniquesRequest {},
        &[(USER_ID_HEADER, OLD_DEVICE)],
    )
    .await;
    assert_eq!(listed.status, tonic::Code::Ok as i32);

    assert!(exists(&db.pool, OLD_DEVICE).await);
    assert!(
        sessions_of(&db.pool, OLD_DEVICE).await.is_empty(),
        "the row is back, but nothing that was filed under it is"
    );
}
