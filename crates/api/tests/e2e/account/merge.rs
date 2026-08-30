//! Identity adoption and transactional history merging.

use std::time::Duration;

use sqlx::PgPool;

use super::fixtures::{
    NEW_DEVICE, OLD_DEVICE, bolt_seconds_of, exists, given_bolt_score, given_own_technique,
    given_quota, given_resting_rate, given_session, own_techniques_of, quota_of, resting_rates_of,
    sessions_of, uuid,
};
use crate::harness::{
    APPLE_ACCOUNT, ScriptedIdentityVerifier, TestDatabase, given_user, sign_in, subscribe,
};

/// Two devices' worth of practice, arranged so every reparenting rule has
/// something to act on: an id both sides hold (one record that reached the
/// server twice — the older identity's copy stays), an id only one side holds
/// (survives), assistant allowance spent on both (summed — keeping the older
/// count would let sign-in launder the new device's spend), and a moved authored exercise.
async fn given_two_devices_with_history(
    pool: &PgPool,
    shared_session: &str,
    shared_score: &str,
    shared_rate: &str,
) {
    given_user(pool, OLD_DEVICE, "Older").await;
    given_session(pool, OLD_DEVICE, shared_session, "kept-on-collision").await;
    given_session(
        pool,
        OLD_DEVICE,
        "5e551011-0000-4000-8000-000000000002",
        "only-on-the-old-device",
    )
    .await;
    given_bolt_score(pool, OLD_DEVICE, shared_score, 30).await;
    given_bolt_score(pool, OLD_DEVICE, "b01f0000-0000-4000-8000-000000000002", 41).await;
    given_resting_rate(pool, OLD_DEVICE, shared_rate, 14).await;
    given_resting_rate(pool, OLD_DEVICE, "4a7e0000-0000-4000-8000-000000000002", 11).await;
    given_quota(pool, OLD_DEVICE, 0, 3).await;
    given_own_technique(pool, OLD_DEVICE, "Written before").await;

    given_user(pool, NEW_DEVICE, "Newer").await;
    given_own_technique(pool, NEW_DEVICE, "Written on the new phone").await;
    given_session(pool, NEW_DEVICE, shared_session, "dropped-on-collision").await;
    given_session(
        pool,
        NEW_DEVICE,
        "5e551011-0000-4000-8000-000000000003",
        "only-on-the-new-device",
    )
    .await;
    // The same score resent, at a value the assertion below could not confuse
    // with the one the old device holds.
    given_bolt_score(pool, NEW_DEVICE, shared_score, 55).await;
    given_bolt_score(pool, NEW_DEVICE, "b01f0000-0000-4000-8000-000000000003", 22).await;
    // The same measurement resent, at a value the assertion below could not
    // confuse with the one the old device holds.
    given_resting_rate(pool, NEW_DEVICE, shared_rate, 27).await;
    given_resting_rate(pool, NEW_DEVICE, "4a7e0000-0000-4000-8000-000000000003", 19).await;
    given_quota(pool, NEW_DEVICE, 0, 2).await;
    given_quota(pool, NEW_DEVICE, 1, 7).await;
}

#[tokio::test]
async fn a_merge_keeps_both_histories_and_sums_a_shared_days_allowance() {
    let db = TestDatabase::create("account_merge").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    let shared_session = "5e551011-0000-4000-8000-000000000001";
    let shared_score = "b01f0000-0000-4000-8000-000000000001";
    let shared_rate = "4a7e0000-0000-4000-8000-000000000001";

    given_two_devices_with_history(&db.pool, shared_session, shared_score, shared_rate).await;

    sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;
    let adopted = sign_in(db.app_with_identity(verifier), NEW_DEVICE, "jws-apple").await;
    assert_eq!(adopted.user_id, OLD_DEVICE);

    assert_eq!(
        sessions_of(&db.pool, OLD_DEVICE).await,
        vec![
            (uuid(shared_session), "kept-on-collision".to_owned()),
            (
                uuid("5e551011-0000-4000-8000-000000000003"),
                "only-on-the-new-device".to_owned()
            ),
            (
                uuid("5e551011-0000-4000-8000-000000000002"),
                "only-on-the-old-device".to_owned()
            ),
        ],
        "one session from each side, and one row for the id both sides held"
    );

    assert_eq!(
        bolt_seconds_of(&db.pool, OLD_DEVICE).await,
        vec![22, 30, 41],
        "55 was the newcomer's copy of a score the old device already had"
    );

    assert_eq!(
        resting_rates_of(&db.pool, OLD_DEVICE).await,
        vec![11, 14, 19],
        "27 was the newcomer's copy of a measurement the old device already had"
    );

    assert_eq!(
        own_techniques_of(&db.pool, OLD_DEVICE).await,
        vec![
            "Written before".to_owned(),
            "Written on the new phone".to_owned()
        ],
        "an exercise somebody wrote exists nowhere else, so both sides' survive"
    );

    let today = quota_of(&db.pool, OLD_DEVICE).await;
    assert_eq!(today.len(), 2, "{today:?}");
    assert_eq!(today[0].1, 7, "yesterday's spend came across untouched");
    assert_eq!(today[1].1, 5, "today is 3 + 2, not 3 and not 2");

    assert!(!exists(&db.pool, NEW_DEVICE).await);
    assert_eq!(
        sqlx::query_scalar!(
            "SELECT display_name FROM users WHERE id = $1",
            uuid(OLD_DEVICE)
        )
        .fetch_one(&db.pool)
        .await
        .expect("the row is readable"),
        Some("Older".to_owned()),
        "the surviving row keeps its own profile answers"
    );
}

/// A sync already in flight when the merge runs is not cascaded away: without
/// the `FOR UPDATE` at the top of `repository::merge`, the reparent runs
/// against a snapshot predating the insert and `DELETE FROM users` destroys it
/// through `ON DELETE CASCADE`. The open transaction holds `FOR KEY SHARE` on
/// the `users` row — a mid-flight `RecordSessions` exactly. Too short a sleep passes either way.
#[tokio::test]
async fn a_sync_in_flight_when_the_merge_runs_is_not_cascaded_away() {
    let db = TestDatabase::create("account_merge_race").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    let in_flight = "5e551011-0000-4000-8000-000000000009";

    given_user(&db.pool, OLD_DEVICE, "Older").await;
    given_user(&db.pool, NEW_DEVICE, "Newer").await;
    sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;

    let mut writer = db.pool.begin().await.expect("a second transaction");
    sqlx::query!(
        "INSERT INTO sessions (
            user_id, client_session_id, technique_slug, started_at,
            duration_ms, cycles_completed, breath_count, completed
         ) VALUES ($1, $2, 'breathed-mid-merge', now(), 60000, 5, 20, true)",
        uuid(NEW_DEVICE),
        uuid(in_flight)
    )
    .execute(&mut *writer)
    .await
    .expect("the in-flight session is written");

    let app = db.app_with_identity(verifier);
    let signing_in = tokio::spawn(async move { sign_in(app, NEW_DEVICE, "jws-apple").await });

    tokio::time::sleep(Duration::from_millis(250)).await;
    writer.commit().await.expect("the in-flight sync lands");

    let adopted = signing_in.await.expect("the sign-in finished");
    assert_eq!(adopted.user_id, OLD_DEVICE);

    assert!(
        sessions_of(&db.pool, OLD_DEVICE)
            .await
            .iter()
            .any(|(id, _)| *id == uuid(in_flight)),
        "the session landed on an identity the merge then deleted"
    );
}

/// A subscription does not ride the merge across, and does not need to:
/// deleting the newcomer releases its `app_store_original_transaction_id`, and
/// the client resubmits its `StoreKit` transaction on every launch, so the
/// entitlement re-lands on the surviving identity against no holder at all.
#[tokio::test]
async fn a_merge_does_not_carry_an_entitlement_across() {
    let db = TestDatabase::create("account_entitlement").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Older").await;
    subscribe(&db.pool, NEW_DEVICE, "PLUS").await;

    sign_in(
        db.app_with_identity(verifier.clone()),
        OLD_DEVICE,
        "jws-apple",
    )
    .await;
    sign_in(db.app_with_identity(verifier), NEW_DEVICE, "jws-apple").await;

    let tier = sqlx::query_scalar!(
        r#"SELECT subscription_tier::text FROM users WHERE id = $1"#,
        uuid(OLD_DEVICE)
    )
    .fetch_one(&db.pool)
    .await
    .expect("the row is readable");

    assert_eq!(
        tier, None,
        "the surviving row was not handed a subscription"
    );
}
