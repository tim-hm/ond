//! `AccountService`, over the wire the iOS client uses, against a scripted
//! Sign in with Apple verifier. Nothing Apple signed anywhere: a real identity
//! token needs Apple's private key and checking one needs a network fetch, so
//! this is the only shape the suite could have. The real verifier is pinned by
//! its unit tests; what the *server* does with a proven account is pinned here.

use std::time::Duration;

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use axum::Router;
use chrono::{DateTime, NaiveDate, TimeDelta, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::harness::{
    APPLE_ACCOUNT, GrpcWebResponse, OTHER_APPLE_ACCOUNT, ScriptedIdentityVerifier, TestDatabase,
    begin_apple_authorization, call_grpc_web_with, given_user, headers, live_credentials, sign_in,
    subscribe, token_with_nonce, try_sign_in, try_sign_in_with_nonce,
};

const DELETE: &str = "/ond.v1.AccountService/DeleteAccount";

/// The identity a person already had — the one a returning sign-in hands back.
const OLD_DEVICE: &str = "acc00000-0000-4000-8000-000000000001";

/// The identity a new device minted on first launch, before signing in.
const NEW_DEVICE: &str = "acc00000-0000-4000-8000-000000000002";

fn uuid(value: &str) -> Uuid {
    value.parse().expect("a valid uuid")
}

async fn try_delete_account(
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

async fn try_delete_with_identity_token(
    app: Router,
    caller: &str,
    credential: Option<&str>,
    identity_token: String,
) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    call_grpc_web_with(
        app,
        DELETE,
        &pb::DeleteAccountRequest { identity_token },
        &headers(caller, credential),
    )
    .await
}

/// Erasure as an anonymous identity asks for it: no credential and an empty
/// token, because the header is the whole of what such a caller has.
async fn delete_account(app: Router, caller: &str) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    try_delete_account(app, caller, None, "").await
}

/// One breathed session. `slug` is what tells two rows sharing a
/// `client_session_id` apart, which is the only way to see which copy a merge
/// kept.
async fn given_session(pool: &PgPool, user: &str, client_session_id: &str, slug: &str) {
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
async fn given_bolt_score(pool: &PgPool, user: &str, client_score_id: &str, seconds: i32) {
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
async fn given_resting_rate(pool: &PgPool, user: &str, client_measurement_id: &str, rate: i32) {
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
async fn given_own_technique(pool: &PgPool, user: &str, name: &str) {
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

async fn own_techniques_of(pool: &PgPool, user: &str) -> Vec<String> {
    sqlx::query_scalar!(
        "SELECT name FROM user_techniques WHERE user_id = $1 ORDER BY name",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the exercises are readable")
}

/// A day's worth of spent allowance, `days_ago` before today's UTC date.
async fn given_quota(pool: &PgPool, user: &str, days_ago: i32, calls: i32) {
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
async fn sessions_of(pool: &PgPool, user: &str) -> Vec<(Uuid, String)> {
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

async fn bolt_seconds_of(pool: &PgPool, user: &str) -> Vec<i32> {
    sqlx::query_scalar!(
        "SELECT seconds FROM bolt_scores WHERE user_id = $1 ORDER BY seconds",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the scores are readable")
}

async fn resting_rates_of(pool: &PgPool, user: &str) -> Vec<i32> {
    sqlx::query_scalar!(
        "SELECT breaths_per_minute FROM resting_rates WHERE user_id = $1
          ORDER BY breaths_per_minute",
        uuid(user)
    )
    .fetch_all(pool)
    .await
    .expect("the rates are readable")
}

async fn quota_of(pool: &PgPool, user: &str) -> Vec<(NaiveDate, i32)> {
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
async fn given_app_store_binding(pool: &PgPool, user: &str, transaction_id: &str) {
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
async fn holder_of_transaction(pool: &PgPool, transaction_id: &str) -> Option<Uuid> {
    sqlx::query_scalar!(
        "SELECT id FROM users WHERE app_store_original_transaction_id = $1",
        transaction_id
    )
    .fetch_optional(pool)
    .await
    .expect("the row is readable")
}

async fn exists(pool: &PgPool, user: &str) -> bool {
    sqlx::query_scalar!("SELECT count(*) FROM users WHERE id = $1", uuid(user))
        .fetch_one(pool)
        .await
        .expect("the count is readable")
        .unwrap_or_default()
        > 0
}

async fn apple_account_of(pool: &PgPool, user: &str) -> Option<String> {
    sqlx::query_scalar!("SELECT apple_user_id FROM users WHERE id = $1", uuid(user))
        .fetch_one(pool)
        .await
        .expect("the row is readable")
}

mod authorization;
mod deletion;
mod merge;
mod sign_in;
