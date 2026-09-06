//! Verification refusals and the access an entitlement grants.

use api::proto::ond::v1 as pb;

use super::fixtures::{
    OTHER_USER, ScriptedVerifier, USER, credential_of, given_signed_in, headers, plus, read, submit,
};
use crate::harness::{SUBMIT_APP_STORE_TRANSACTION, TestDatabase, call_grpc_web_with, subscribe};

/// A token the verifier refuses buys nothing and says so as `INVALID_ARGUMENT`,
/// not as a quietly free entitlement. The distinction is what lets the client
/// tell a broken submission apart from a lapsed subscription.
#[tokio::test]
async fn an_unverifiable_transaction_is_refused() {
    let db = TestDatabase::create("entitlement_forged").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![]);

    let response = call_grpc_web_with::<_, pb::SubmitAppStoreTransactionResponse>(
        db.app_with_verifier(verifier.clone()),
        SUBMIT_APP_STORE_TRANSACTION,
        &pb::SubmitAppStoreTransactionRequest {
            signed_transaction: "forged".to_owned(),
        },
        &headers(USER, &credential_of(USER)),
    )
    .await;

    assert_eq!(response.status, tonic::Code::InvalidArgument as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await.tier,
        pb::EntitlementTier::Free as i32
    );
}

/// An entitlement is one person's. The purchase is stored against the caller in
/// the header, so somebody else reading with their own identity sees nothing —
/// the same containment `ProfileService` and `JourneyService` rely on, pinned
/// separately here because this is the one it costs money to get wrong.
#[tokio::test]
async fn one_persons_purchase_does_not_entitle_another() {
    let db = TestDatabase::create("entitlement_isolation").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    let other = read(db.app_with_verifier(verifier), OTHER_USER).await;
    assert_eq!(other.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(other.expires_at, None);
}

/// The tier is derived on every read rather than stored, so a subscription that
/// ran out answers FREE with nothing having run in between. Written straight
/// into the columns, because there is no way to make Apple's clock move.
#[tokio::test]
async fn an_expiry_in_the_past_reads_as_free() {
    let db = TestDatabase::create("entitlement_lapsed").await;
    let verifier = ScriptedVerifier::with(vec![]);

    // The row is created by the identity layer on the first RPC of any kind, so
    // one call has to happen before there is anything to expire.
    read(db.app_with_verifier(verifier.clone()), USER).await;

    subscribe(&db.pool, USER, "PLUS").await;
    sqlx::query("UPDATE users SET subscription_until = now() - interval '1 day' WHERE id = $1")
        .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
        .execute(&db.pool)
        .await
        .expect("the expiry is written");

    let entitlement = read(db.app_with_verifier(verifier), USER).await;
    assert_eq!(entitlement.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(entitlement.expires_at, None);
}
