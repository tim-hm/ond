//! First, returning, and refused Sign in with Apple bindings.

use super::*;

/// The first sign-in on an Apple account nobody holds: the binding lands on
/// the caller's own row and the caller keeps its id. Signing in again is
/// asserted alongside because the client will — a launch that finds an Apple
/// credential still valid re-presents it, and that must be the same identity
/// rather than an error.
#[tokio::test]
async fn a_first_sign_in_binds_the_caller_and_keeps_its_id() {
    let db = TestDatabase::create("account_first").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        "jws-apple",
    )
    .await;
    assert_eq!(signed_in.user_id, NEW_DEVICE);
    assert_eq!(
        apple_account_of(&db.pool, NEW_DEVICE).await.as_deref(),
        Some(APPLE_ACCOUNT),
        "the binding is what makes the identity findable from another device"
    );

    // Carrying the credential the first sign-in returned, because the row is
    // bound now and `identity::resolve` refuses one that cannot prove itself —
    // on this RPC like every other.
    let again = try_sign_in(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        Some(&signed_in.credential),
        "jws-apple",
    )
    .await
    .into_ok();

    assert_eq!(again.user_id, signed_in.user_id);
    assert_ne!(
        again.session_credential, signed_in.credential,
        "each sign-in mints its own, so signing out of one device leaves the other alone"
    );
}

/// The whole point of the feature: a new phone mints an identity of its own,
/// signs in, and is handed back the one this Apple account already had.
///
/// The device's own row is gone afterwards rather than left orphaned — a row
/// nothing can reach again is a row nothing will ever delete.
#[tokio::test]
async fn a_returning_sign_in_hands_back_the_identity_the_account_already_had() {
    let db = TestDatabase::create("account_returning").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    let adopted = sign_in(db.app_with_identity(verifier), NEW_DEVICE, "jws-apple").await;

    assert_eq!(adopted.user_id, OLD_DEVICE);
    assert!(!exists(&db.pool, NEW_DEVICE).await);
    assert!(
        !adopted.credential.is_empty(),
        "the identity it adopted is bound, so the device is refused everything without one"
    );
}

/// A token the verifier refuses binds nothing, and says so as `UNAUTHENTICATED`
/// rather than as a quietly successful sign-in. The identity a client would
/// persist off a successful response is the whole of its future access, so
/// "rejected" and "you are now this person" must never be confusable.
#[tokio::test]
async fn an_unverifiable_token_binds_nothing() {
    let db = TestDatabase::create("account_forged").await;
    let verifier = ScriptedIdentityVerifier::refusing();

    let response = try_sign_in(db.app_with_identity(verifier), NEW_DEVICE, None, "forged").await;

    assert_eq!(response.status, tonic::Code::Unauthenticated as i32);
    assert_eq!(apple_account_of(&db.pool, NEW_DEVICE).await, None);
}

/// An installation already signed in to one Apple account is refused a second,
/// rather than silently rebound. Rebinding would drop the first account's only
/// route back to its history — `apple_user_id` is the sole record of it — and
/// the refusal is the answer that loses nothing.
#[tokio::test]
async fn an_installation_bound_to_one_apple_account_is_refused_a_second() {
    let db = TestDatabase::create("account_rebind").await;
    let verifier = ScriptedIdentityVerifier::with(vec![
        ("jws-apple", APPLE_ACCOUNT),
        ("jws-other", OTHER_APPLE_ACCOUNT),
    ]);

    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        "jws-apple",
    )
    .await;

    let response = try_sign_in(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        Some(&signed_in.credential),
        "jws-other",
    )
    .await;

    assert_eq!(response.status, tonic::Code::FailedPrecondition as i32);
    assert_eq!(
        apple_account_of(&db.pool, NEW_DEVICE).await.as_deref(),
        Some(APPLE_ACCOUNT),
        "the first account keeps the row it is the only record of"
    );
}

/// The same refusal on the merge path, where an unguarded branch made it
/// destructive: `repository::merge` asked nothing about the caller's own
/// binding, so the row bound to the first Apple account was reparented into
/// the second and deleted — the only record that account had a history at all.
/// The outcome must not turn on whether the second account happens to have a row yet.
#[tokio::test]
async fn an_installation_bound_to_one_apple_account_is_not_merged_into_another() {
    let db = TestDatabase::create("account_rebind_merge").await;
    let verifier = ScriptedIdentityVerifier::with(vec![
        ("jws-apple", APPLE_ACCOUNT),
        ("jws-other", OTHER_APPLE_ACCOUNT),
    ]);

    sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;
    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        "jws-other",
    )
    .await;

    let response = try_sign_in(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        Some(&signed_in.credential),
        "jws-apple",
    )
    .await;

    assert_eq!(
        response.status,
        tonic::Code::FailedPrecondition as i32,
        "the same status the claim path returns, so a client needs no second case"
    );
    assert!(
        exists(&db.pool, NEW_DEVICE).await,
        "a refused sign-in does not delete the identity that made it"
    );
    assert_eq!(
        apple_account_of(&db.pool, NEW_DEVICE).await.as_deref(),
        Some(OTHER_APPLE_ACCOUNT),
        "the caller's own Apple account is the only route back to its history"
    );
    assert_eq!(
        apple_account_of(&db.pool, OLD_DEVICE).await.as_deref(),
        Some(APPLE_ACCOUNT),
        "the account signed in to is untouched by the refusal"
    );
}
