//! `AccountService`, over the wire the iOS client uses, against a scripted
//! Sign in with Apple verifier.
//!
//! Nothing Apple signed anywhere, and nothing that could go looking for it:
//! every token here is a bare string the scripted verifier maps to an Apple
//! account. A real identity token needs Apple's private key, and checking one
//! needs a key fetched from Apple over the network — so this is the only shape
//! the suite could have. What the real verifier does with real bytes is pinned by
//! the unit tests beside it; what the *server* does with a proven Apple account
//! is pinned here.

use std::time::Duration;

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use axum::Router;
use chrono::NaiveDate;
use sqlx::PgPool;
use uuid::Uuid;

use crate::harness::{
    APPLE_ACCOUNT, GrpcWebResponse, OTHER_APPLE_ACCOUNT, ScriptedIdentityVerifier, TestDatabase,
    call_grpc_web_with, headers, live_credentials, sign_in, subscribe, try_sign_in,
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
    let request = pb::DeleteAccountRequest {
        identity_token: token.to_owned(),
    };

    call_grpc_web_with(app, DELETE, &request, &headers(caller, credential)).await
}

/// Erasure as an anonymous identity asks for it: no credential and an empty
/// token, because the header is the whole of what such a caller has.
async fn delete_account(app: Router, caller: &str) -> GrpcWebResponse<pb::DeleteAccountResponse> {
    try_delete_account(app, caller, None, "").await
}

/// A user row, as the identity layer would have created it on the device's first
/// RPC.
///
/// Written directly rather than by making a call, so a test can lay out both
/// sides of a merge before either of them signs in.
async fn given_user(pool: &PgPool, user: &str, display_name: &str) {
    sqlx::query!(
        "INSERT INTO users (id, display_name) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name",
        uuid(user),
        display_name
    )
    .execute(pool)
    .await
    .expect("the user row is written");
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

/// The first sign-in on an Apple account nobody holds: the binding lands on the
/// caller's own row and the caller keeps its id, so nothing on the device has to
/// change.
///
/// Signing in again is asserted alongside it because the client will: a launch
/// that finds an Apple credential still valid re-presents it, and that must be
/// the same identity rather than an error.
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

/// The merge, with history on both sides and a collision in the middle of it.
///
/// Three rules in one test because they are one transaction: a session and a
/// score held by only one side survive on the older identity; a
/// client-generated id held by *both* is one record that reached the server
/// twice, so the older identity's copy stays and the newcomer's is dropped; a
/// day's assistant allowance spent on both is summed rather than replaced —
/// keeping the older count would let signing in launder whatever the new device
/// had already spent; and an exercise somebody composed moves with no collision
/// guard at all, because its id is the server's rather than the client's and it
/// exists nowhere else to be reconstructed from.
/// Two devices' worth of practice, arranged so that every reparenting rule the
/// merge follows has something to act on: an id both sides hold, an id only one
/// side holds, and — for each of the two measurements — the same pair again.
///
/// Its own function because the arrangement is most of the test and clippy says
/// so; the assertions are what the test is about, and they read better without
/// forty lines of setup above them.
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

/// A sync that is already in flight when the merge runs is not cascaded away.
///
/// The window is narrow and the writer is the same device that is signing in, so
/// it is not fanciful: a `RecordSessions` call and a `SignInWithApple` call can
/// overlap, and both name the identity that is about to stop existing.
///
/// Without the `FOR UPDATE` at the top of `repository::merge`, the reparent runs
/// against a snapshot that predates the insert, the insert then commits, and
/// `DELETE FROM users` destroys it through `ON DELETE CASCADE` — a silent loss of
/// exactly the history the merge exists to preserve. The lock makes the merge
/// wait for the writer instead, so the reparent's own snapshot includes it.
///
/// The open transaction is the mechanism: an insert into `sessions` takes
/// `FOR KEY SHARE` on the referenced `users` row and holds it until commit, which
/// is precisely the state a `RecordSessions` call is in mid-flight. The sleep only
/// has to be long enough for the sign-in to reach the merge; too short and the
/// writer simply commits first, which is a case that passes either way — so this
/// test can be insensitive but never flaky.
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

/// A subscription does not ride the merge across, and does not need to.
///
/// Deleting the newcomer releases its `app_store_original_transaction_id`
/// outright, and the client resubmits its `StoreKit` transaction on every launch —
/// so the entitlement re-lands on the surviving identity against no holder at
/// all. Copying it here would mean reasoning about the unique constraint and the
/// transfer cooldown for an outcome the next launch produces by itself.
#[tokio::test]
async fn a_merge_does_not_carry_an_entitlement_across() {
    let db = TestDatabase::create("account_entitlement").await;
    let verifier = ScriptedIdentityVerifier::with(vec![("jws-apple", APPLE_ACCOUNT)]);

    given_user(&db.pool, OLD_DEVICE, "Older").await;
    subscribe(&db.pool, NEW_DEVICE, "COACH").await;

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
/// rather than silently rebound.
///
/// Rebinding would drop the first account's only route back to its history —
/// `apple_user_id` is the sole record of it — and the person doing this is
/// reachable only by a client that skipped signing out, so the refusal is the
/// answer that loses nothing.
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
/// destructive rather than merely wrong.
///
/// This is the case above with one thing changed: somebody already holds the
/// account being signed in to. That sent the call down `repository::merge`, which
/// asked nothing about the caller's own binding — so the row bound to the first
/// Apple account was reparented into the second and deleted, taking with it the
/// only record that the first account had a history at all. Whether a bound
/// caller was refused or silently absorbed turned entirely on whether the second
/// account happened to have a row yet, which is not a distinction the caller can
/// see or the server should act on.
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
    subscribe(&db.pool, OLD_DEVICE, "COACH").await;
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
/// in the API. `bind_apple_account` already refuses to let possession of an
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
