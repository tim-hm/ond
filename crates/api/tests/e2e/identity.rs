//! `identity::resolve` — the choke point every gRPC request passes through, and
//! the one place a signed-in identity is made to prove itself.
//!
//! Its own suite rather than a section of `account.rs`, because the behaviour is
//! not `AccountService`'s: the credential is minted there, but what it buys is
//! enforced under every service in the API. Several tests below therefore assert
//! on `TechniqueService`, which is public reference data and wants no identity at
//! all — a refusal there is proof the check happens before any handler chooses to
//! make it.

use api::proto::ond::v1 as pb;
use axum::Router;
use sqlx::PgPool;
use uuid::Uuid;

use crate::harness::{
    self, APPLE_ACCOUNT, OTHER_APPLE_ACCOUNT, ScriptedIdentityVerifier, TestDatabase,
    call_grpc_web_with, headers, live_credentials, try_sign_in,
};

const SIGN_OUT: &str = "/ond.v1.AccountService/SignOut";
const LIST_TECHNIQUES: &str = "/ond.v1.TechniqueService/ListTechniques";
const GET_PROFILE: &str = "/ond.v1.ProfileService/GetProfile";

const USER: &str = "1de7717a-0000-4000-8000-000000000001";
const OTHER_USER: &str = "1de7717a-0000-4000-8000-000000000002";

/// A router whose Sign in with Apple verifier accepts the two tokens this suite
/// uses and refuses everything else.
fn app(db: &TestDatabase) -> Router {
    db.app_with_identity(ScriptedIdentityVerifier::with(vec![
        ("jws-apple", APPLE_ACCOUNT),
        ("jws-other", OTHER_APPLE_ACCOUNT),
    ]))
}

/// Signs in through [`harness::sign_in`] and returns the credential, plus the
/// assertions every caller here shares: they sign in to an account nobody
/// holds, so the id must come back unchanged with a credential attached.
async fn sign_in(db: &TestDatabase, caller: &str, token: &str) -> String {
    let signed_in = harness::sign_in(app(db), caller, token).await;

    assert_eq!(
        signed_in.user_id, caller,
        "these callers all sign in to an account nobody holds"
    );
    assert!(
        !signed_in.credential.is_empty(),
        "a sign-in that returns no credential locks the client out of the id it just adopted"
    );

    signed_in.credential
}

/// The catalogue, asked for under one identity and whatever it can prove.
///
/// `TechniqueService` is the deliberate choice: it answers an anonymous caller
/// perfectly well, so nothing about the RPC itself could be doing the refusing.
async fn list_techniques(app: Router, user: &str, credential: Option<&str>) -> i32 {
    call_grpc_web_with::<_, pb::ListTechniquesResponse>(
        app,
        LIST_TECHNIQUES,
        &pb::ListTechniquesRequest {},
        &headers(user, credential),
    )
    .await
    .status
}

/// A scoped RPC, for the half of the rule that is about somebody's own data
/// rather than about the choke point.
async fn get_profile(app: Router, user: &str, credential: Option<&str>) -> i32 {
    call_grpc_web_with::<_, pb::GetProfileResponse>(
        app,
        GET_PROFILE,
        &pb::GetProfileRequest {},
        &headers(user, credential),
    )
    .await
    .status
}

async fn sign_out(app: Router, user: &str, credential: Option<&str>) -> i32 {
    call_grpc_web_with::<_, pb::SignOutResponse>(
        app,
        SIGN_OUT,
        &pb::SignOutRequest {},
        &headers(user, credential),
    )
    .await
    .status
}

async fn is_bound(pool: &PgPool, user: &str) -> bool {
    sqlx::query_scalar!(
        r#"SELECT (apple_user_id IS NOT NULL) AS "bound!" FROM users WHERE id = $1"#,
        user.parse::<Uuid>().expect("a valid uuid")
    )
    .fetch_optional(pool)
    .await
    .expect("the row is readable")
    .unwrap_or(false)
}

/// The whole of what this change is for: once a row is bound to an Apple
/// account, the id alone stops being enough.
///
/// The id is what the app puts on the Settings screen with a copy button, and a
/// subscription now hangs off it — so before this, everything a signed-in person
/// had was reachable by anybody who read that value over their shoulder. The
/// refusal is asserted on `TechniqueService`, which needs no identity of its own:
/// it can only be `identity::resolve`, before any handler.
#[tokio::test]
async fn a_signed_in_identity_is_refused_without_its_credential() {
    let db = TestDatabase::create("identity_bound_needs_credential").await;

    let credential = sign_in(&db, USER, "jws-apple").await;

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Unauthenticated as i32,
        "possession of the id was the entire claim, and this is the line where it stops being"
    );
    assert_eq!(
        get_profile(app(&db), USER, None).await,
        tonic::Code::Unauthenticated as i32
    );

    assert_eq!(
        list_techniques(app(&db), USER, Some(&credential)).await,
        tonic::Code::Ok as i32,
        "and the person who signed in is not locked out of their own account"
    );
    assert_eq!(
        get_profile(app(&db), USER, Some(&credential)).await,
        tonic::Code::Ok as i32
    );
}

/// The other side of the rule, and the one that would be quietly catastrophic to
/// break: an identity that has never signed in is asked for nothing.
///
/// Local-only mode is the majority of people. They have no Apple account, no
/// credential and nothing to prove, and a check that fell through to them would
/// lock every one of them out of an app that never had accounts in the first
/// place. The wrong credential is submitted deliberately: an unbound row is
/// refused nothing *whatever the request carries*, which is what a client still
/// holding a stale value after signing out actually sends.
#[tokio::test]
async fn an_anonymous_identity_is_asked_for_nothing() {
    let db = TestDatabase::create("identity_anonymous_unchanged").await;

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Ok as i32
    );
    assert_eq!(
        get_profile(app(&db), USER, None).await,
        tonic::Code::Ok as i32
    );
    assert_eq!(
        list_techniques(app(&db), USER, Some("a credential nobody minted")).await,
        tonic::Code::Ok as i32,
        "an unbound row has nothing to prove, so there is nothing a header could fail to prove"
    );

    assert!(!is_bound(&db.pool, USER).await);
    assert_eq!(live_credentials(&db.pool, USER).await, 0);
}

/// A credential proves one identity, not the fact of having signed in somewhere.
///
/// The `EXISTS` in `repository::standing` is scoped to the row being resolved,
/// and this is what would notice if it stopped being: an attacker who holds a
/// stolen bound id and their own perfectly valid credential would otherwise walk
/// straight in.
#[tokio::test]
async fn a_credential_proves_only_the_identity_it_was_minted_for() {
    let db = TestDatabase::create("identity_credential_scope").await;

    let mine = sign_in(&db, USER, "jws-apple").await;
    let theirs = sign_in(&db, OTHER_USER, "jws-other").await;

    assert_eq!(
        list_techniques(app(&db), USER, Some(&theirs)).await,
        tonic::Code::Unauthenticated as i32
    );
    assert_eq!(
        list_techniques(app(&db), OTHER_USER, Some(&mine)).await,
        tonic::Code::Unauthenticated as i32
    );

    assert_eq!(
        list_techniques(app(&db), USER, Some(&mine)).await,
        tonic::Code::Ok as i32
    );
}

/// Signing out revokes the credential and leaves everything else standing.
///
/// The two halves are one test because the failure modes are opposite: a
/// sign-out that revoked nothing leaves a live credential on a device somebody
/// has just handed on, and one that took the account with it destroys a history
/// the person only meant to stop using here. The row survives, still bound, and
/// signing in again on a fresh identity is what recovers it.
#[tokio::test]
async fn signing_out_revokes_the_credential_and_keeps_the_account() {
    let db = TestDatabase::create("identity_sign_out").await;

    let credential = sign_in(&db, USER, "jws-apple").await;
    assert_eq!(live_credentials(&db.pool, USER).await, 1);

    assert_eq!(
        sign_out(app(&db), USER, Some(&credential)).await,
        tonic::Code::Ok as i32
    );

    assert_eq!(live_credentials(&db.pool, USER).await, 0);
    assert!(
        is_bound(&db.pool, USER).await,
        "signing out is not asking to be forgotten"
    );
    assert_eq!(
        list_techniques(app(&db), USER, Some(&credential)).await,
        tonic::Code::Unauthenticated as i32,
        "the credential the device still holds proves nothing now"
    );
}

/// Signing out on one device leaves the other signed in.
///
/// `end_session` deletes the credential the request was made with rather than
/// every credential the identity holds, and this is the difference: a person who
/// signs out on a phone they are selling must not be signed out on the one in
/// their pocket. Reached by signing in twice on the same Apple account, which is
/// exactly what a second device does.
#[tokio::test]
async fn signing_out_on_one_device_leaves_another_signed_in() {
    let db = TestDatabase::create("identity_sign_out_one_device").await;

    let first = sign_in(&db, USER, "jws-apple").await;

    // The second device: a fresh identity signing in to an account somebody
    // already holds, which is handed back that identity and a credential of its
    // own.
    let second = try_sign_in(app(&db), OTHER_USER, None, "jws-apple")
        .await
        .into_ok();
    assert_eq!(
        second.user_id, USER,
        "the second device adopts the first's id"
    );
    assert_eq!(live_credentials(&db.pool, USER).await, 2);

    assert_eq!(
        sign_out(app(&db), USER, Some(&first)).await,
        tonic::Code::Ok as i32
    );

    assert_eq!(
        list_techniques(app(&db), USER, Some(&first)).await,
        tonic::Code::Unauthenticated as i32
    );
    assert_eq!(
        list_techniques(app(&db), USER, Some(&second.session_credential)).await,
        tonic::Code::Ok as i32,
        "the device that did not sign out is still signed in"
    );
}

/// An anonymous caller signing out is answered `OK` having had nothing to
/// revoke.
///
/// The client clears its own state either way — signing out of local-only mode
/// is a person tapping a button that does nothing on the server — and a refusal
/// here would give a client a failure it can neither act on nor report.
#[tokio::test]
async fn signing_out_without_a_credential_succeeds_and_changes_nothing() {
    let db = TestDatabase::create("identity_sign_out_anonymous").await;

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Ok as i32,
        "the row exists before the sign-out, so a missing one is not what is being asserted"
    );

    assert_eq!(sign_out(app(&db), USER, None).await, tonic::Code::Ok as i32);

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Ok as i32
    );
    assert_eq!(live_credentials(&db.pool, USER).await, 0);
}

/// A client that lost its credential is not stranded — but it does have to come
/// back the way a new device does.
///
/// There is no exemption for `SignInWithApple`: a bound id with nothing to prove
/// it is refused at the middleware, on that RPC like every other. The route back
/// is the one restoring onto a new phone already takes, and it is the reason no
/// exemption is needed: mint a fresh anonymous id, sign in on that, and the Apple
/// account hands the identity back with a credential attached.
#[tokio::test]
async fn a_lost_credential_is_recovered_by_signing_in_on_a_fresh_identity() {
    let db = TestDatabase::create("identity_lost_credential").await;

    sign_in(&db, USER, "jws-apple").await;

    // The device still has the id and no longer has the credential.
    let stranded = try_sign_in(app(&db), USER, None, "jws-apple").await;
    assert_eq!(stranded.status, tonic::Code::Unauthenticated as i32);

    let recovered = try_sign_in(app(&db), OTHER_USER, None, "jws-apple")
        .await
        .into_ok();

    assert_eq!(
        recovered.user_id, USER,
        "the Apple account is the route back"
    );
    assert_eq!(
        list_techniques(app(&db), USER, Some(&recovered.session_credential)).await,
        tonic::Code::Ok as i32
    );
}

/// The watch race, closed at the choke point: an id a sign-in merge folded away
/// stays dead instead of being recreated as a fresh anonymous row
/// (`0019_merged_identities.sql` tells the story). Asserted on
/// `TechniqueService`, which answers anonymous callers happily, so the refusal
/// can only be `identity::resolve`.
#[tokio::test]
async fn a_merged_away_identity_stays_dead() {
    let db = TestDatabase::create("identity_merged_away").await;

    sign_in(&db, OTHER_USER, "jws-apple").await;

    // The same person's phone, previously anonymous, signs in to that account:
    // its id is folded into the holder's and retired.
    let merged = try_sign_in(app(&db), USER, None, "jws-apple").await;
    assert_eq!(
        merged.into_ok().user_id,
        OTHER_USER,
        "signing in to a held account adopts the holder's id"
    );

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Unauthenticated as i32,
        "the retired id is refused rather than resurrected"
    );

    // Including the sign-in RPC itself: a phone that lost the merge's response
    // recovers by minting a fresh id and signing in on that (`AccountModel`
    // implements exactly this), never by resurrecting the dead one.
    let retried = try_sign_in(app(&db), USER, None, "jws-apple").await;
    assert_eq!(retried.status, tonic::Code::Unauthenticated as i32);

    let recreated = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM users WHERE id = $1) AS "exists!""#,
        USER.parse::<Uuid>().expect("a valid uuid")
    )
    .fetch_one(&db.pool)
    .await
    .expect("the row is countable");
    assert!(!recreated, "and no orphan row is created for it");
}

/// Erasing the account releases the ids that were merged into it.
///
/// The tombstone's `ON DELETE CASCADE` is the deliberate half of the schema:
/// once the account is gone there is no history for a stale id to strand, so
/// the id returns to the ordinary recreate-empty path — the same answer
/// `DeleteAccount` already gives the id it erases directly.
#[tokio::test]
async fn deleting_the_account_releases_its_merged_ids() {
    let db = TestDatabase::create("identity_merge_tombstones_released").await;

    sign_in(&db, OTHER_USER, "jws-apple").await;
    try_sign_in(app(&db), USER, None, "jws-apple")
        .await
        .into_ok();

    // The erasure itself is `DeleteAccount`'s ceremony; the cascade is the
    // schema's. Deleting the row directly exercises exactly the cascade.
    sqlx::query!(
        "DELETE FROM users WHERE id = $1",
        OTHER_USER.parse::<Uuid>().expect("a valid uuid")
    )
    .execute(&db.pool)
    .await
    .expect("the account row deletes");

    assert_eq!(
        list_techniques(app(&db), USER, None).await,
        tonic::Code::Ok as i32,
        "with the account gone, the old id is an ordinary fresh identity again"
    );
}

/// The 90-day sweep `0020_user_sessions_expiry.sql` promises, and the refresh
/// that keeps a living session out of its way: a credential is bounded by
/// disuse, never by age. The idle credential belongs to an abandoned device —
/// presenting one *is* use and would refresh it, so what sweeps it is the one
/// thing that can grow the table: somebody else's sign-in.
#[tokio::test]
async fn a_credential_is_bounded_by_disuse_not_by_age() {
    let db = TestDatabase::create("identity_session_sweep").await;

    let idle = sign_in(&db, USER, "jws-apple").await;
    // The device this credential lived on went silent 91 days ago.
    sqlx::query!("UPDATE user_sessions SET last_seen_at = now() - interval '91 days'")
        .execute(&db.pool)
        .await
        .expect("the session backdates");

    let live = sign_in(&db, OTHER_USER, "jws-other").await;

    assert_eq!(
        get_profile(app(&db), USER, Some(&idle)).await,
        tonic::Code::Unauthenticated as i32,
        "ninety days of silence is a credential swept"
    );

    // Backdated past the bound again: expiry is lazy, so the profile read
    // below still answers — and refreshes the clock, which is then the only
    // thing standing between this credential and the next sweep. The third
    // sign-in that runs that sweep is a fresh install joining the second
    // account, which is a merge and not a helper-shaped first sign-in.
    sqlx::query!("UPDATE user_sessions SET last_seen_at = now() - interval '91 days'")
        .execute(&db.pool)
        .await
        .expect("the session backdates");
    assert_eq!(
        get_profile(app(&db), OTHER_USER, Some(&live)).await,
        tonic::Code::Ok as i32
    );

    try_sign_in(
        app(&db),
        "1de7717a-0000-4000-8000-000000000003",
        None,
        "jws-other",
    )
    .await
    .into_ok();

    assert_eq!(
        get_profile(app(&db), OTHER_USER, Some(&live)).await,
        tonic::Code::Ok as i32,
        "the use reset the clock, or this sweep would have taken it"
    );
}
