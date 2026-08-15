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
    begin_apple_authorization, build_app_with, call_grpc_web_with, subscribe, token_with_nonce,
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
    subscription_period(
        original_transaction_id,
        original_transaction_id,
        tier,
        expires_in,
    )
}

/// One individually named period inside a subscription lineage.
fn subscription_period(
    transaction_id: &str,
    original_transaction_id: &str,
    tier: SubscriptionTier,
    expires_in: Duration,
) -> VerifiedTransaction {
    let sequence = FIXTURE_SEQUENCE.fetch_add(1, Ordering::Relaxed);

    VerifiedTransaction {
        transaction_id: transaction_id.to_owned(),
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
    refund_period(original_transaction_id, original_transaction_id)
}

/// A refund for one named period, signed after fixtures built before it.
fn refund_period(transaction_id: &str, original_transaction_id: &str) -> VerifiedTransaction {
    VerifiedTransaction {
        revoked_at: Some(Utc::now()),
        ..subscription_period(
            transaction_id,
            original_transaction_id,
            SubscriptionTier::Plus,
            MONTH,
        )
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
    let challenge = begin_apple_authorization(
        app.clone(),
        user,
        Some(&credential),
        pb::AppleAuthorizationPurpose::DeleteAccount,
    )
    .await
    .into_ok();

    call_grpc_web_with::<_, pb::DeleteAccountResponse>(
        app,
        DELETE_ACCOUNT,
        &pb::DeleteAccountRequest {
            identity_token: token_with_nonce(&token, &challenge.nonce),
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

mod access;
mod ownership;
mod purchase;
mod refunds;
