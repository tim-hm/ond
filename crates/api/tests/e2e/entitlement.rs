//! `EntitlementService`, over the wire the iOS client uses, against a scripted
//! App Store verifier.
//!
//! No Apple-signed material anywhere. Every transaction here is a bare string
//! the scripted verifier maps to a payload, which is the only way this suite
//! could exist — a real `jwsRepresentation` needs Apple's private key, and one
//! captured from a sandbox purchase would go stale the moment its certificate
//! chain rotated. What the real verifier does with real bytes is pinned by the
//! unit tests beside it; what the *server* does with a verified transaction is
//! pinned here.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};

use api::entitlement::{
    SubscriptionTier, Tier, TransactionVerifier, VerificationError, VerifiedTransaction,
};
use api::identity::{CredentialHash, SESSION_CREDENTIAL_HEADER, USER_ID_HEADER};
use api::proto::ond::v1 as pb;
use axum::Router;
use chrono::{Duration, Utc};
use sqlx::PgPool;

use crate::harness::{
    self, GrpcWebResponse, ScriptedIdentityVerifier, ScriptedModel, TestDatabase, allowance,
    build_app_with, call_grpc_web_with, subscribe,
};

const SUBMIT: &str = "/ond.v1.EntitlementService/SubmitAppStoreTransaction";
const GET: &str = "/ond.v1.EntitlementService/GetEntitlement";
const DELETE_ACCOUNT: &str = "/ond.v1.AccountService/DeleteAccount";

const USER: &str = "e07171e0-0000-4000-8000-000000000001";
const OTHER_USER: &str = "e07171e0-0000-4000-8000-000000000002";

/// Both products renew monthly, so a fixture's period is a month unless the
/// test is specifically about a longer one.
const MONTH: Duration = Duration::days(30);

/// A verifier that knows a fixed set of tokens and rejects everything else.
///
/// Keyed on the token string so a test can submit "the same JWS" twice and mean
/// it — the idempotency being asserted is about the transaction id inside, and a
/// verifier that minted a fresh id per call would make that untestable. The
/// script itself is never mutated after construction, which is what lets it be
/// shared without a lock.
struct ScriptedVerifier {
    transactions: HashMap<String, VerifiedTransaction>,

    /// How often the seam was reached. The only way to assert that a submission
    /// was refused *before* the token was read, which is the whole content of
    /// the size bound.
    reads: AtomicUsize,
}

impl ScriptedVerifier {
    fn with(tokens: Vec<(&str, VerifiedTransaction)>) -> Arc<Self> {
        Arc::new(Self {
            transactions: tokens
                .into_iter()
                .map(|(token, transaction)| (token.to_owned(), transaction))
                .collect(),
            reads: AtomicUsize::new(0),
        })
    }

    fn reads(&self) -> usize {
        self.reads.load(Ordering::Relaxed)
    }
}

impl TransactionVerifier for ScriptedVerifier {
    fn verify(&self, signed_transaction: &str) -> Result<VerifiedTransaction, VerificationError> {
        self.reads.fetch_add(1, Ordering::Relaxed);

        self.transactions
            .get(signed_transaction)
            .cloned()
            .ok_or_else(|| VerificationError::Untrusted("scripted rejection".to_owned()))
    }
}

/// Signing dates advance a second per fixture built.
///
/// `Utc::now()` for all of them would be correct in principle and flaky in
/// practice: the column stores microseconds, and two fixtures constructed in one
/// expression can land in the same one — at which point the server's `<`
/// correctly refuses the second as not newer, and a test that meant them as a
/// sequence fails perhaps one run in ten. A counter makes "built later" and
/// "signed later" the same fact.
static FIXTURE_SEQUENCE: AtomicI64 = AtomicI64::new(0);

/// One purchase, signed after every fixture built before it.
fn subscription(
    original_transaction_id: &str,
    tier: SubscriptionTier,
    expires_in: Duration,
) -> VerifiedTransaction {
    let sequence = FIXTURE_SEQUENCE.fetch_add(1, Ordering::Relaxed);

    VerifiedTransaction {
        original_transaction_id: original_transaction_id.to_owned(),
        tier,
        expires_at: Utc::now() + expires_in,
        signed_at: Utc::now() + Duration::seconds(sequence),
        revoked_at: None,
    }
}

/// The subscription most tests want: a month of Plus.
fn plus(original_transaction_id: &str) -> VerifiedTransaction {
    subscription(original_transaction_id, SubscriptionTier::Plus, MONTH)
}

/// A refund, signed after the purchase it revokes — which is both what Apple
/// sends and what the ordering rule requires to let it through.
fn refund(original_transaction_id: &str) -> VerifiedTransaction {
    VerifiedTransaction {
        revoked_at: Some(Utc::now()),
        ..plus(original_transaction_id)
    }
}

/// Apple's `sub` for an identity this suite signed in, derived from the id so
/// two callers cannot collide on the column's `UNIQUE`.
fn apple_account_of(user: &str) -> String {
    format!("001234.{user}.0001")
}

/// The session credential the identity `user` proves itself with once
/// [`given_signed_in`] has minted one.
///
/// Derived from the id rather than returned from the write, so that every helper
/// below needs nothing but the id it already has and no test threads a value
/// through. Unique per identity, which `user_sessions` requires — the hash is
/// its primary key.
fn credential_of(user: &str) -> String {
    format!("{user}-session-credential")
}

/// The headers a client sends for `user`.
///
/// Always both, including for the callers this suite never signs in. That is
/// what a real client does — it sends whatever it is holding, and a credential
/// left over from a previous account is a value it has not cleared yet — and an
/// unbound row is refused nothing whatever the request carries.
fn headers<'a>(user: &'a str, credential: &'a str) -> [(&'a str, &'a str); 2] {
    [
        (USER_ID_HEADER, user),
        (SESSION_CREDENTIAL_HEADER, credential),
    ]
}

/// Puts a caller in the state a verified `SignInWithApple` leaves them in: bound
/// to an Apple account, holding one live credential.
///
/// Not a precondition of buying — a submission asks nothing about an Apple
/// account, which `an_anonymous_purchase_recovers_onto_a_new_identity` pins.
/// `delete_account` needs it, because `identity::resolve` demands a credential
/// the moment a row is bound; the rest of the suite keeps it because a bound row
/// is the stricter setup, so a break in the identity layer fails these tests
/// rather than passing unseen.
///
/// Written straight into the two tables rather than driven through
/// `AccountService`, for the reason `subscribe` is: this suite is about what a
/// purchase is worth, and how somebody came to be signed in is the account
/// suite's question.
async fn given_signed_in(pool: &PgPool, user: &str) {
    let id = user.parse::<uuid::Uuid>().expect("a valid uuid");

    sqlx::query(
        "INSERT INTO users (id, apple_user_id) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET apple_user_id = EXCLUDED.apple_user_id",
    )
    .bind(id)
    .bind(apple_account_of(user))
    .execute(pool)
    .await
    .expect("the binding is written");

    sqlx::query("INSERT INTO user_sessions (token_hash, user_id) VALUES ($1, $2)")
        .bind(CredentialHash::of(&credential_of(user)).as_bytes())
        .bind(id)
        .execute(pool)
        .await
        .expect("the credential is written");
}

async fn try_submit(
    app: Router,
    user: &str,
    token: &str,
) -> GrpcWebResponse<pb::SubmitAppStoreTransactionResponse> {
    let request = pb::SubmitAppStoreTransactionRequest {
        signed_transaction: token.to_owned(),
    };
    let credential = credential_of(user);

    call_grpc_web_with(app, SUBMIT, &request, &headers(user, &credential)).await
}

async fn submit(app: Router, user: &str, token: &str) -> pb::Entitlement {
    try_submit(app, user, token)
        .await
        .into_ok()
        .entitlement
        .expect("every response carries an entitlement")
}

/// Erases the caller, as the account feature's own suite does — needed here
/// because the thing a revocation has to survive is a deletion, and asserting
/// that through the wire is the only way to know the two features agree.
///
/// Builds its own router rather than taking one, because the caller it erases is
/// bound to an Apple account — not because buying required that, which it does
/// not, but because [`given_signed_in`] bound it. Erasing a bound row needs a
/// fresh identity token whose `sub` is that binding, so this is the one call in
/// the suite whose router has to have an identity verifier that accepts
/// something.
async fn delete_account(db: &TestDatabase, user: &str) -> i32 {
    let token = format!("{user}-apple-token");
    let app = build_app_with(
        db.pool.clone(),
        Arc::new(api::assistant::DisabledModelClient),
        ScriptedVerifier::with(vec![]),
        ScriptedIdentityVerifier::with(vec![(&token, &apple_account_of(user))]),
    );
    let credential = credential_of(user);

    call_grpc_web_with::<_, pb::DeleteAccountResponse>(
        app,
        DELETE_ACCOUNT,
        &pb::DeleteAccountRequest {
            identity_token: token.clone(),
        },
        &headers(user, &credential),
    )
    .await
    .status
}

async fn read(app: Router, user: &str) -> pb::Entitlement {
    let credential = credential_of(user);

    call_grpc_web_with::<_, pb::GetEntitlementResponse>(
        app,
        GET,
        &pb::GetEntitlementRequest {},
        &headers(user, &credential),
    )
    .await
    .into_ok()
    .entitlement
    .expect("every response carries an entitlement")
}

/// No `subscribe` here, unlike `assistant.rs`'s helper of the same name: this
/// suite exists to find out who may reach the model, so a tier is always the
/// thing a test has set up for itself.
async fn recommend(
    db: &TestDatabase,
    model: Arc<ScriptedModel>,
    verifier: Arc<ScriptedVerifier>,
    user: &str,
) -> pb::GetRecommendationResponse {
    harness::recommend_as(
        build_app_with(
            db.pool.clone(),
            model,
            verifier,
            ScriptedIdentityVerifier::refusing(),
        ),
        user,
        Some(&credential_of(user)),
        None,
    )
    .await
}

/// The happy path, and the only one that mints an entitlement: a transaction
/// the verifier accepts becomes a tier and an expiry the next call reads back.
/// Asserted through a second RPC rather than the submission's own response,
/// because what matters is that it was *stored*.
#[tokio::test]
async fn a_verified_transaction_becomes_a_readable_entitlement() {
    let db = TestDatabase::create("entitlement_grant").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let submitted = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(submitted.tier, pb::EntitlementTier::Plus as i32);
    assert!(submitted.expires_at.is_some());

    let stored = read(db.app_with_verifier(verifier), USER).await;
    assert_eq!(stored.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(stored.expires_at, submitted.expires_at);
}

/// Somebody who has never bought anything is FREE with no date, not `NOT_FOUND`
/// and not an error. The client renders a paywall from this, so an error here
/// would make "not subscribed" indistinguishable from "the server is down" —
/// and the app is supposed to work offline.
#[tokio::test]
async fn a_caller_who_has_bought_nothing_is_free() {
    let db = TestDatabase::create("entitlement_default").await;
    let verifier = ScriptedVerifier::with(vec![]);

    let entitlement = read(db.app_with_verifier(verifier), USER).await;

    assert_eq!(entitlement.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(entitlement.expires_at, None);
}

/// The client resubmits on every launch — that is its whole retry strategy — so
/// the same token arriving repeatedly has to be one entitlement rather than an
/// error or a second grant. The expiry not moving is the assertion that matters:
/// an implementation that extended the period per submission would pass a test
/// that only checked the tier.
#[tokio::test]
async fn resubmitting_the_same_transaction_changes_nothing() {
    let db = TestDatabase::create("entitlement_idempotent").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let first = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let second = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let third = submit(db.app_with_verifier(verifier), USER, "jws-plus").await;

    assert_eq!(first, second);
    assert_eq!(second, third);
    assert_eq!(first.tier, pb::EntitlementTier::Plus as i32);
}

/// The reason the ordering key is `signedDate` and not the expiry.
///
/// Upgrading Plus to Coach mid-month issues a Coach transaction whose expiry is
/// *earlier* than the annual Plus period it replaced. Ordering by expiry — which
/// is what M8 did, before there were two products — keeps the Plus row and
/// leaves somebody paying for Coach and holding Plus. Ordering by `signedDate`
/// takes the whole newer row, shorter expiry and all.
#[tokio::test]
async fn an_upgrade_is_not_shadowed_by_a_longer_cheaper_period() {
    let db = TestDatabase::create("entitlement_upgrade").await;
    given_signed_in(&db.pool, USER).await;
    // Built in the order they were signed — the counter is what makes that the
    // same statement — so the Coach upgrade is the newer transaction despite
    // carrying the shorter period.
    let long_plus = subscription(
        "2000000000000001",
        SubscriptionTier::Plus,
        Duration::days(365),
    );
    let short_coach = subscription("2000000000000002", SubscriptionTier::Coach, MONTH);

    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus-year", long_plus),
        ("jws-coach-month", short_coach),
    ]);

    let before = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-plus-year",
    )
    .await;
    let after = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-coach-month",
    )
    .await;

    assert_eq!(after.tier, pb::EntitlementTier::Coach as i32);
    assert!(
        after.expires_at.map(|at| at.seconds) < before.expires_at.map(|at| at.seconds),
        "the upgrade's own shorter period is what the person now holds"
    );

    // And the client resubmitting the superseded Plus transaction on its next
    // launch — which it will, because `currentEntitlements` and
    // `Transaction.updates` have no ordering between them — must not take the
    // upgrade away again.
    let resubmitted = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-plus-year",
    )
    .await;
    assert_eq!(resubmitted, after);
    assert_eq!(read(db.app_with_verifier(verifier), USER).await, after);
}

/// A refund revokes — and only the subscription it paid for. The transaction
/// still verifies and its expiry is still in the future; what ends the
/// entitlement is the revocation date, and nothing else in the payload says so.
///
/// The unrelated refund is the half that could not be seen from the other:
/// somebody who let one subscription lapse, bought another, and then had the old
/// one refunded must keep what they are still paying for.
#[tokio::test]
async fn a_refund_ends_only_the_subscription_it_paid_for() {
    let db = TestDatabase::create("entitlement_revoked").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        ("jws-other-refund", refund("2000000000000009")),
    ]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    let unrelated = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-other-refund",
    )
    .await;
    assert_eq!(unrelated, bought);

    let after_refund = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(after_refund.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(after_refund.expires_at, None);
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        after_refund
    );
}

/// A refund is final, and the transaction that paid for it is still in the
/// client's hands.
///
/// The revoked transaction and the purchase it revokes are the *same*
/// subscription, and the purchase's payload carries no `revocationDate` — so it
/// verifies perfectly, forever, until its own expiry. What stops it re-granting
/// is that the revocation leaves the ordering marker set to its own `signedDate`
/// rather than clearing it; an earlier submission then loses the comparison it
/// would otherwise win against a null.
///
/// Reachable by an honest client, not only an attacker: `Transaction.updates`
/// and `currentEntitlements` have no ordering between them, so a single launch
/// can hand the server the refund and then the purchase.
///
/// Buying again afterwards has to still work, which is the half a fix could
/// easily break — hence the third submission.
#[tokio::test]
async fn a_refund_cannot_be_undone_by_resubmitting() {
    let db = TestDatabase::create("entitlement_refund_replay").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        ("jws-bought-again", plus("2000000000000002")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let refunded = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(refunded.tier, pb::EntitlementTier::Free as i32);

    let replayed = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(replayed.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), USER).await,
        refunded
    );

    let bought_again = submit(
        db.app_with_verifier(verifier.clone()),
        USER,
        "jws-bought-again",
    )
    .await;
    assert_eq!(bought_again.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        bought_again
    );
}

/// The same finality, through the one door that used to lead around it.
///
/// Every defence in the test above is state on the `users` row: the surviving
/// binding, and the ordering marker the revocation leaves set. `DeleteAccount`
/// deletes that row. So the sequence was tap delete, let the client mint a fresh
/// UUID — which it must, and which the app does automatically — and resubmit the
/// pre-refund transaction the client still holds. Nothing held the binding,
/// nothing lost the ordering comparison, and the refunded tier came back until
/// the period Apple had already refunded expired.
///
/// Bounded, and not the point: the property the previous audit's critical was
/// fixed to establish is that a refund is final, and "final unless you delete
/// your account" is a different property. `revoked_transactions` is a fact about
/// the transaction rather than about the person, so erasure cannot reach it.
#[tokio::test]
async fn a_refund_is_not_undone_by_deleting_the_account_and_starting_again() {
    let db = TestDatabase::create("entitlement_refund_after_delete").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let refunded = submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;
    assert_eq!(refunded.tier, pb::EntitlementTier::Free as i32);

    let erased = delete_account(&db, USER).await;
    assert_eq!(erased, tonic::Code::Ok as i32);

    // The fresh identity the app mints the instant a deletion returns, carrying
    // the same transaction `StoreKit` still hands it on every launch.
    let replayed = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(replayed.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier), OTHER_USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "and nothing was written for a later call to read back"
    );
}

/// The half the tombstone could easily have broken: a refund ends the purchase
/// it names, not the subscription's whole future.
///
/// `originalTransactionId` is stable across every renewal of one subscription,
/// so the revocation is filed under an id the *next* payment carries too.
/// Refusing on the row's presence alone would leave somebody who was refunded
/// one period and went on paying — or who resubscribed within the group —
/// permanently Free, with nothing on the server able to put it right. What the
/// replay defence needs is the ordering the row-level guard already has: signed
/// before Apple revoked, or signed after.
#[tokio::test]
async fn a_purchase_signed_after_a_refund_still_entitles() {
    let db = TestDatabase::create("entitlement_refund_then_renewal").await;
    given_signed_in(&db.pool, USER).await;
    // Built in the order they were signed, which is the order Apple issues them
    // in: bought, refunded, and then paid for again under the same lineage.
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        ("jws-refunded", refund("2000000000000001")),
        ("jws-renewed", plus("2000000000000001")),
    ]);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    submit(db.app_with_verifier(verifier.clone()), USER, "jws-refunded").await;

    let renewed = submit(db.app_with_verifier(verifier.clone()), USER, "jws-renewed").await;
    assert_eq!(renewed.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(read(db.app_with_verifier(verifier), USER).await, renewed);
}

/// A `jwsRepresentation` is a string. Somebody can copy it off their own device
/// and submit it from any client under any UUID they mint, and nothing inside
/// the token names who may use it — so the binding has to come from the server.
///
/// This is money rather than principle. Coach's whole content is the language
/// model and its allowance is counted per user per UTC day, so one shared token
/// fanning out across self-minted identities is uncapped provider spend against
/// a per-user ceiling.
#[tokio::test]
async fn a_purchase_entitles_one_identity_at_a_time() {
    let db = TestDatabase::create("entitlement_replay").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![(
        "jws-coach",
        subscription("2000000000000001", SubscriptionTier::Coach, MONTH),
    )]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-coach").await;

    let replayed = try_submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-coach",
    )
    .await;
    assert_eq!(replayed.status, tonic::Code::PermissionDenied as i32);

    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), OTHER_USER)
            .await
            .tier,
        pb::EntitlementTier::Free as i32
    );
    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await,
        bought,
        "the buyer keeps what they bought"
    );
}

/// The other half of the binding, and the case the original schema comment chose
/// not to bind at all for: there is no account recovery, so somebody who
/// reinstalls and reaches this app with a new identity and the same Apple ID has
/// to be able to take their purchase with them.
///
/// The transaction therefore moves rather than being refused outright — but only
/// once it has sat still for the cooldown, because a binding that moved on demand
/// would be the same fan-out taken in turns, one daily allowance at a time.
/// Backdated in the column, because there is no way to make the clock move.
#[tokio::test]
async fn a_settled_purchase_follows_its_owner_to_a_new_identity() {
    let db = TestDatabase::create("entitlement_transfer").await;
    given_signed_in(&db.pool, USER).await;
    given_signed_in(&db.pool, OTHER_USER).await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;

    sqlx::query(
        "UPDATE users SET subscription_claimed_at = now() - interval '2 days' WHERE id = $1",
    )
    .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
    .execute(&db.pool)
    .await
    .expect("the claim is backdated");

    let moved = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(moved.tier, bought.tier);
    assert_eq!(moved.expires_at, bought.expires_at);

    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "the transaction moved rather than being shared"
    );
}

/// A real `jwsRepresentation` is a few kilobytes; without a bound the only
/// ceiling is tonic's 4 MiB decode limit, and every byte under it would be
/// split, base64-decoded three times and JSON-parsed on a path with no rate
/// limit in front of it. The verifier's read count is the assertion that
/// matters: rejecting the oversized token *after* doing the work would pass a
/// test that only checked the status.
#[tokio::test]
async fn a_token_too_large_to_be_a_transaction_is_refused_unread() {
    let db = TestDatabase::create("entitlement_oversized").await;
    given_signed_in(&db.pool, USER).await;
    let verifier = ScriptedVerifier::with(vec![]);

    let oversized = "j".repeat(64 * 1024);
    let response = try_submit(db.app_with_verifier(verifier.clone()), USER, &oversized).await;

    assert_eq!(response.status, tonic::Code::InvalidArgument as i32);
    assert_eq!(verifier.reads(), 0, "nothing decoded it to find out");
}

/// Subscribing asks nothing about an Apple account: an identity that has only
/// ever been a UUID buys, and reads back what it bought.
///
/// The rule this replaces refused exactly this caller, on the grounds that a
/// purchase hanging off a bare UUID could not be recovered onto a new phone. The
/// second half of the test is why that was never true. The anchor under a
/// subscription is the App Store account: the new phone mints a fresh identity,
/// Restore Purchases hands the server the same signed transaction, and the
/// entitlement moves — with neither identity having ever signed in.
///
/// Both halves, in one test, because the claim is one claim. The transfer rule
/// itself, including the cooldown that bounds it, is
/// `a_settled_purchase_follows_its_owner_to_a_new_identity`'s.
#[tokio::test]
async fn an_anonymous_purchase_recovers_onto_a_new_identity() {
    let db = TestDatabase::create("entitlement_anonymous").await;
    let verifier = ScriptedVerifier::with(vec![("jws-plus", plus("2000000000000001"))]);

    let bought = submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    assert_eq!(bought.tier, pb::EntitlementTier::Plus as i32);
    assert_eq!(
        read(db.app_with_verifier(verifier.clone()), USER).await,
        bought
    );

    // Backdated because there is no way to make the clock move: what the person
    // experiences is a purchase made some days before the phone was replaced.
    sqlx::query(
        "UPDATE users SET subscription_claimed_at = now() - interval '2 days' WHERE id = $1",
    )
    .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
    .execute(&db.pool)
    .await
    .expect("the claim is backdated");

    let restored = submit(
        db.app_with_verifier(verifier.clone()),
        OTHER_USER,
        "jws-plus",
    )
    .await;
    assert_eq!(restored.tier, bought.tier);
    assert_eq!(restored.expires_at, bought.expires_at);

    assert_eq!(
        read(db.app_with_verifier(verifier), USER).await.tier,
        pb::EntitlementTier::Free as i32,
        "the transaction moved rather than being shared"
    );
}

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
        SUBMIT,
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

/// The tier decides nothing about the model any more, and this is the test that
/// says so from the outside. It used to assert the opposite — that only Coach
/// reached the provider — and it is kept, inverted, rather than deleted:
/// buying a subscription is exactly the event that could quietly restore a gate
/// nobody meant to restore, and this is the only place a purchase and a model
/// call meet in one test.
///
/// What binds instead is the ceiling, which is not a tier gate. It is per
/// person per UTC day, so climbing the ladder mid-day does not hand anybody a
/// fresh pool — the calls made while free are still spent once Coach lands.
/// Asserted through the model's own call count, because every tier gets an
/// answer either way and only the count says whether one was paid for.
#[tokio::test]
async fn every_tier_reaches_the_model_on_one_shared_ceiling() {
    let db = TestDatabase::create("entitlement_model_access").await;
    given_signed_in(&db.pool, USER).await;

    let ceiling = allowance(Tier::Free);
    assert!(ceiling > 0, "the model is reachable without paying");
    assert_eq!(allowance(Tier::Plus), ceiling);
    assert_eq!(allowance(Tier::Coach), ceiling);

    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));
    let verifier = ScriptedVerifier::with(vec![
        ("jws-plus", plus("2000000000000001")),
        (
            "jws-coach",
            subscription("2000000000000002", SubscriptionTier::Coach, MONTH),
        ),
    ]);

    // One call at each rung of the ladder, in the order somebody would climb
    // it. The assertion is that all three read the same.
    let free_answer = recommend(&db, model.clone(), verifier.clone(), USER).await;
    assert_eq!(free_answer.source, pb::AssistantSource::Model as i32);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-plus").await;
    let plus_answer = recommend(&db, model.clone(), verifier.clone(), USER).await;
    assert_eq!(plus_answer.source, pb::AssistantSource::Model as i32);

    submit(db.app_with_verifier(verifier.clone()), USER, "jws-coach").await;
    let coach_answer = recommend(&db, model.clone(), verifier.clone(), USER).await;
    assert_eq!(coach_answer.source, pb::AssistantSource::Model as i32);

    let rungs = model.calls();
    assert_eq!(rungs, 3, "a purchase neither buys nor costs a call");

    // The rest of the day's pool, spent from where the rungs left it rather
    // than from zero — counted off the model so the loop cannot disagree with
    // what was actually spent above it.
    while model.calls() < ceiling {
        let answer = recommend(&db, model.clone(), verifier.clone(), USER).await;
        assert_eq!(answer.source, pb::AssistantSource::Model as i32);
    }

    // Past the ceiling: the rule-based list, flagged as a wait that ends at
    // midnight rather than as something to buy.
    let exhausted = recommend(&db, model.clone(), verifier, USER).await;
    assert_eq!(exhausted.source, pb::AssistantSource::Fallback as i32);
    assert!(!exhausted.recommendations.is_empty());
    assert_eq!(
        model.calls(),
        ceiling,
        "upgrading mid-day did not reset the counter"
    );
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

    subscribe(&db.pool, USER, "COACH").await;
    sqlx::query("UPDATE users SET subscription_until = now() - interval '1 day' WHERE id = $1")
        .bind(USER.parse::<uuid::Uuid>().expect("a valid uuid"))
        .execute(&db.pool)
        .await
        .expect("the expiry is written");

    let entitlement = read(db.app_with_verifier(verifier), USER).await;
    assert_eq!(entitlement.tier, pb::EntitlementTier::Free as i32);
    assert_eq!(entitlement.expires_at, None);
}
