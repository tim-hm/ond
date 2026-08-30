//! What every account test builds its world out of.
//!
//! Here rather than in each file because all four suites lay out rows and read
//! them back the same way, and a hand-written INSERT per suite is one more
//! place to update when a table grows a column.

use api::proto::ond::v1 as pb;
use axum::Router;
use chrono::NaiveDate;
use sqlx::PgPool;
use uuid::Uuid;

use crate::harness::{
    DELETE_ACCOUNT, GrpcWebResponse, begin_apple_authorization, call_grpc_web_with, headers,
    token_with_nonce,
};

/// The identity a person already had — the one a returning sign-in hands back.
pub(super) const OLD_DEVICE: &str = "acc00000-0000-4000-8000-000000000001";

/// The identity a new device minted on first launch, before signing in.
pub(super) const NEW_DEVICE: &str = "acc00000-0000-4000-8000-000000000002";

pub(super) fn uuid(value: &str) -> Uuid {
    value.parse().expect("a valid uuid")
}

pub(super) async fn try_delete_account(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    token: &str,
) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    let identity_token = if token.is_empty() {
        String::new()
    } else {
        let challenge = begin_apple_authorization(
            app.clone(),
            caller,
            credential,
            pb::AppleAuthorizationPurpose::DeleteAccount,
        )
        .await
        .into_ok();
        token_with_nonce(token, &challenge.nonce)
    };
    try_delete_with_identity_token(app, caller, credential, identity_token).await
}

pub(super) async fn try_delete_with_identity_token(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    identity_token: String,
) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    call_grpc_web_with(
        app,
        DELETE_ACCOUNT,
        &pb::DeleteAccountRequest { identity_token },
        &headers(caller, credential),
    )
    .await
}

/// Erasure as an anonymous identity asks for it: no credential and an empty
/// token, because the header is the whole of what such a caller has.
pub(super) async fn delete_account(
    app: Router,
    caller: &str,
) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    try_delete_account(app, caller, None, "").await
}

/// One breathed session. `slug` is what tells two rows sharing a
/// `client_session_id` apart, which is the only way to see which copy a merge
/// kept.
pub(super) async fn given_session(pool: &PgPool, user: &str, client_session_id: &str, slug: &str) {
    sqlx::query!(
        "INSERT INTO sessions (
            user_id, client_session_id, technique_slug, started_at,
            duration_ms, cycles_completed, breath_count, completed
         ) VALUES ($1, $2, $3, now(), 60000, 5, 20, true)",
        uuid(user),
        uuid(client_session_id),
        slug
    )
    .execute(pool)
    .await
    .expect("the session is written");
}

/// One controlled pause. `seconds` plays the part `slug` does for a session.
pub(super) async fn given_bolt_score(
    pool: &PgPool,
    user: &str,
    client_score_id: &str,
    seconds: i32,
) {
    sqlx::query!(
        "INSERT INTO bolt_scores (user_id, client_score_id, seconds) VALUES ($1, $2, $3)",
        uuid(user),
        uuid(client_score_id),
        seconds
    )
    .execute(pool)
    .await
    .expect("the score is written");
}

/// One resting-rate measurement. Beside [`given_bolt_score`] because the merge
/// treats the two identically, and a test that covered only one would not notice
/// a table left out of the reparenting.
pub(super) async fn given_resting_rate(
    pool: &PgPool,
    user: &str,
    client_measurement_id: &str,
    rate: i32,
) {
    sqlx::query!(
        "INSERT INTO resting_rates (user_id, client_measurement_id, breaths_per_minute)
         VALUES ($1, $2, $3)",
        uuid(user),
        uuid(client_measurement_id),
        rate
    )
    .execute(pool)
    .await
    .expect("the rate is written");
}

/// One exercise this person composed, written directly for the same reason the
/// sessions above are.
pub(super) async fn given_own_technique(pool: &PgPool, user: &str, name: &str) {
    sqlx::query!(
        "INSERT INTO user_techniques (user_id, name, goal, rounds)
         VALUES ($1, $2, 'CALM', 1)",
        uuid(user),
        name
    )
    .execute(pool)
    .await
    .expect("the exercise is written");
}

pub(super) async fn own_techniques_of(pool: &PgPool, user: &str) -> Vec<String> {
    sqlx::query_scalar!(
        "SELECT name FROM user_techniques WHERE user_id = $1 ORDER BY name",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the exercises are readable")
}

/// A day's worth of spent allowance, `days_ago` before today's UTC date.
pub(super) async fn given_quota(pool: &PgPool, user: &str, days_ago: i32, calls: i32) {
    sqlx::query!(
        "INSERT INTO assistant_usage (user_id, usage_date, calls)
         VALUES ($1, CURRENT_DATE - $2::integer, $3)",
        uuid(user),
        days_ago,
        calls
    )
    .execute(pool)
    .await
    .expect("the quota row is written");
}

/// Every session on one identity, as `(client_session_id, technique_slug)`.
pub(super) async fn sessions_of(pool: &PgPool, user: &str) -> Vec<(Uuid, String)> {
    sqlx::query!(
        "SELECT client_session_id, technique_slug FROM sessions
          WHERE user_id = $1 ORDER BY technique_slug",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the sessions are readable")
    .into_iter()
    .map(|row| (row.client_session_id, row.technique_slug))
    .collect()
}

pub(super) async fn bolt_seconds_of(pool: &PgPool, user: &str) -> Vec<i32> {
    sqlx::query_scalar!(
        "SELECT seconds FROM bolt_scores WHERE user_id = $1 ORDER BY seconds",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the scores are readable")
}

pub(super) async fn resting_rates_of(pool: &PgPool, user: &str) -> Vec<i32> {
    sqlx::query_scalar!(
        "SELECT breaths_per_minute FROM resting_rates WHERE user_id = $1
          ORDER BY breaths_per_minute",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the rates are readable")
}

pub(super) async fn quota_of(pool: &PgPool, user: &str) -> Vec<(NaiveDate, i32)> {
    sqlx::query!(
        "SELECT usage_date, calls FROM assistant_usage WHERE user_id = $1 ORDER BY usage_date",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the quota is readable")
    .into_iter()
    .map(|row| (row.usage_date, row.calls))
    .collect()
}

/// The App Store binding, written straight onto the row the way
/// `EntitlementService` writes it. Separate from `subscribe` because it is the
/// one subscription column a deletion has to *release* rather than merely erase.
pub(super) async fn given_app_store_binding(pool: &PgPool, user: &str, transaction_id: &str) {
    sqlx::query!(
        "UPDATE users
            SET app_store_original_transaction_id = $2, subscription_claimed_at = now()
          WHERE id = $1",
        uuid(user),
        transaction_id
    )
    .execute(pool)
    .await
    .expect("the binding is written");
}

/// Which identity holds an App Store transaction, or none.
pub(super) async fn holder_of_transaction(pool: &PgPool, transaction_id: &str) -> Option<Uuid> {
    sqlx::query_scalar!(
        "SELECT id FROM users WHERE app_store_original_transaction_id = $1",
        transaction_id
    )
    .fetch_optional(pool)
    .await
    .expect("the row is readable")
}

pub(super) async fn exists(pool: &PgPool, user: &str) -> bool {
    sqlx::query_scalar!("SELECT count(*) FROM users WHERE id = $1", uuid(user))
        .fetch_one(pool)
        .await
        .expect("the count is readable")
        .unwrap_or_default()
        > 0
}

pub(super) async fn apple_account_of(pool: &PgPool, user: &str) -> Option<String> {
    sqlx::query_scalar!("SELECT apple_user_id FROM users WHERE id = $1", uuid(user))
        .fetch_one(pool)
        .await
        .expect("the row is readable")
}
