//! Anonymous and Apple-bound account erasure behavior.

use super::*;

/// The promise `web/privacy.html` makes, asserted table by table: nothing
/// survives erasure. Each child table is checked by name rather than trusting
/// `ON DELETE CASCADE` — a table added with `SET NULL` or no foreign key would
/// leave history behind while everything else passed. The Apple account and
/// transaction are checked as claimable again: both are `UNIQUE`, so a leftover locks the person out.
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

/// A signed-in account is not erasable by whoever holds its anonymous id —
/// the weakest credential in the system, a UUID a person is invited to paste
/// into a support email — and this is the only irreversible operation in the
/// API. The successful deletion at the end is the half a refusal could break:
/// the credential is a gate, not a wall, and somebody who signs in must still be able to leave.
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
/// account — so the `sub` has to match the binding; anybody with an Apple ID
/// and somebody else's id can reach this. `PERMISSION_DENIED` rather than
/// `UNAUTHENTICATED`: nothing is wrong with the credential, and a client told
/// otherwise would send the person to re-authenticate as the wrong account forever.
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

/// A sign-in landing between the credential being weighed and the row being
/// deleted does not lose the account it just bound. The two halves cannot be
/// one statement — verifying with Apple is a network round trip no transaction
/// may be held across — so the erasure re-reads the binding under a lock and
/// refuses if it changed. The sleep is what puts the bind in flight during the deletion.
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
/// is erased on the header alone. Most people never sign in and the header is
/// the whole of their claim — demanding more would put erasure out of reach.
/// The token here is *unverifiable*, not merely absent, which pins that an
/// anonymous erasure never reaches the verifier at all.
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

/// The reason the client mints a fresh identity the instant this returns:
/// `identity::resolve` upserts a row for any well-formed id it holds no merge
/// tombstone for — and an erasure writes none, deliberately — so one later
/// request on the old id brings the row back, empty and unreachable. The only
/// server-side defence would be a record of every id ever erased — the opposite of the ask.
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
