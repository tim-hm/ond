//! Apple authorization challenges and identity-token resource bounds.

use api::proto::ond::v1 as pb;
use chrono::{DateTime, TimeDelta, Utc};

use super::fixtures::{
    NEW_DEVICE, OLD_DEVICE, apple_account_of, exists, try_delete_with_identity_token, uuid,
};
use crate::harness::{
    APPLE_ACCOUNT, GrpcWebResponse, ScriptedIdentityVerifier, TestDatabase,
    begin_apple_authorization, call_grpc_web_with, headers, live_credentials, sign_in,
    try_sign_in_with_nonce,
};

#[tokio::test]
async fn an_apple_authorization_requires_a_purpose() {
    let db = TestDatabase::create("account_challenge_purpose").await;

    let response = begin_apple_authorization(
        db.app(),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::Unspecified,
    )
    .await;

    assert_eq!(response.status, tonic::Code::InvalidArgument as i32);
}

#[tokio::test]
async fn the_challenge_response_and_row_share_one_five_minute_expiry() {
    let db = TestDatabase::create("account_challenge_expiry").await;

    let challenge = begin_apple_authorization(
        db.app(),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    let wire = challenge.expires_at.expect("the expiry is required");
    let wire_expiry = DateTime::from_timestamp(
        wire.seconds,
        u32::try_from(wire.nanos).expect("a non-negative nanosecond"),
    )
    .expect("a representable challenge expiry");
    let stored_expiry = sqlx::query_scalar!(
        "SELECT expires_at FROM apple_authorization_challenges WHERE user_id = $1",
        uuid(NEW_DEVICE)
    )
    .fetch_one(&db.pool)
    .await
    .expect("the challenge is persisted");

    assert_eq!(stored_expiry, wire_expiry);
    let remaining = wire_expiry - Utc::now();
    assert!(remaining <= TimeDelta::minutes(5));
    assert!(remaining > TimeDelta::minutes(4));
}

#[tokio::test]
async fn a_sign_in_requires_a_live_challenge_for_this_caller_and_purpose() {
    let db = TestDatabase::create("account_challenge_scope").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    let missing = try_sign_in_with_nonce(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        "jws-apple",
        "never-issued",
    )
    .await;
    assert_eq!(missing.status, tonic::Code::Unauthenticated as i32);

    let wrong_caller = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    let wrong_caller = try_sign_in_with_nonce(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        "jws-apple",
        &wrong_caller.nonce,
    )
    .await;
    assert_eq!(wrong_caller.status, tonic::Code::Unauthenticated as i32);

    let wrong_purpose = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::DeleteAccount,
    )
    .await
    .into_ok();
    let wrong_purpose = try_sign_in_with_nonce(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        None,
        "jws-apple",
        &wrong_purpose.nonce,
    )
    .await;
    assert_eq!(wrong_purpose.status, tonic::Code::Unauthenticated as i32);
    assert_eq!(apple_account_of(&db.pool, NEW_DEVICE).await, None);
}

#[tokio::test]
async fn a_challenge_expires_and_a_consumed_one_cannot_be_replayed() {
    let db = TestDatabase::create("account_challenge_lifetime").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    let expired = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    sqlx::query!(
        "UPDATE apple_authorization_challenges SET expires_at = now() - interval '1 second'
          WHERE user_id = $1",
        uuid(NEW_DEVICE)
    )
    .execute(&db.pool)
    .await
    .expect("the test challenge expires");

    let refused = try_sign_in_with_nonce(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        "jws-apple",
        &expired.nonce,
    )
    .await;
    assert_eq!(refused.status, tonic::Code::Unauthenticated as i32);

    let challenge = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    let signed_in = try_sign_in_with_nonce(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        "jws-apple",
        &challenge.nonce,
    )
    .await
    .into_ok();
    let replay = try_sign_in_with_nonce(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        Some(&signed_in.session_credential),
        "jws-apple",
        &challenge.nonce,
    )
    .await;

    assert_eq!(replay.status, tonic::Code::Unauthenticated as i32);
    assert_eq!(live_credentials(&db.pool, NEW_DEVICE).await, 1);
}

#[tokio::test]
async fn two_sign_ins_racing_on_one_challenge_admit_exactly_one() {
    let db = TestDatabase::create("account_challenge_race").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);
    let challenge = begin_apple_authorization(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        None,
        pb::AppleAuthorizationPurpose::SignIn,
    )
    .await
    .into_ok();
    let first_app = db.app_with_identity(verifier.clone());
    let second_app = db.app_with_identity(verifier);

    let (first, second) = tokio::join!(
        try_sign_in_with_nonce(first_app, NEW_DEVICE, None, "jws-apple", &challenge.nonce,),
        try_sign_in_with_nonce(second_app, NEW_DEVICE, None, "jws-apple", &challenge.nonce,),
    );

    let statuses = [first.status, second.status];
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == tonic::Code::Ok as i32)
            .count(),
        1
    );
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == tonic::Code::Unauthenticated as i32)
            .count(),
        1
    );
    assert_eq!(
        apple_account_of(&db.pool, NEW_DEVICE).await.as_deref(),
        Some(APPLE_ACCOUNT)
    );
    assert_eq!(live_credentials(&db.pool, NEW_DEVICE).await, 1);
}

#[tokio::test]
async fn identity_tokens_are_bounded_before_verification() {
    let db = TestDatabase::create("account_token_ceiling").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);
    let oversized = "x".repeat(8 * 1024 + 1);
    let request = pb::SignInWithAppleRequest {
        identity_token: oversized,
    };

    let response: GrpcWebResponse<pb::SignInWithAppleResponse> = call_grpc_web_with(
        db.app_with_identity(verifier.clone()),
        crate::harness::SIGN_IN,
        &request,
        &headers(NEW_DEVICE, None),
    )
    .await;

    assert_eq!(response.status, tonic::Code::InvalidArgument as i32);

    let signed_in = sign_in(
        db.app_with_identity(verifier.clone()),
        NEW_DEVICE,
        "jws-apple",
    )
    .await;
    let deletion = try_delete_with_identity_token(
        db.app_with_identity(verifier),
        NEW_DEVICE,
        Some(&signed_in.credential),
        "x".repeat(8 * 1024 + 1),
    )
    .await;

    assert_eq!(deletion.status, tonic::Code::InvalidArgument as i32);
    assert!(exists(&db.pool, NEW_DEVICE).await);
}
