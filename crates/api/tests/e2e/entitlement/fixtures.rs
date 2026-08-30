//! What every entitlement test builds its world out of.
//!
//! Here rather than in each file because all four suites buy and revoke the
//! same way, and a second scripted verifier is a second place for a signing
//! date to drift.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};

pub(super) use api::entitlement::{
    StoreEnvironment, SubscriptionTier, Tier, TransactionVerifier, VerificationError,
    VerifiedTransaction,
};
use api::identity::{CredentialHash, SESSION_CREDENTIAL_HEADER, USER_ID_HEADER};
pub(super) use api::proto::ond::v1 as pb;
use axum::Router;
pub(super) use chrono::{Duration, Utc};
use sqlx::PgPool;

pub(super) use crate::harness::{
    self, GrpcWebResponse, ScriptedIdentityVerifier, ScriptedModel, TestDatabase, allowance,
    begin_apple_authorization, build_app_with, call_grpc_web_with, subscribe, token_with_nonce,
};

pub(super) const SUBMIT: &str = "/ond.v1.EntitlementService/SubmitAppStoreTransaction";
pub(super) const GET: &str = "/ond.v1.EntitlementService/GetEntitlement";
pub(super) const DELETE_ACCOUNT: &str = "/ond.v1.AccountService/DeleteAccount";

pub(super) const USER: &str = "e07171e0-0000-4000-8000-000000000001";
pub(super) const OTHER_USER: &str = "e07171e0-0000-4000-8000-000000000002";

/// Both products renew monthly, so a fixture's period is a month unless the
/// test is specifically about a longer one.
pub(super) const MONTH: Duration = Duration::days(30);

/// A verifier that knows a fixed set of tokens and rejects everything else.
/// Keyed on the token string so a test can submit "the same JWS" twice and
/// mean it — a verifier minting a fresh id per call would make idempotency
/// untestable. The script is never mutated after construction, which is what
/// lets it be shared without a lock.
pub(super) struct ScriptedVerifier {
    transactions: HashMap<String, VerifiedTransaction>,

    /// How often the seam was reached. The only way to assert that a submission
    /// was refused *before* the token was read, which is the whole content of
    /// the size bound.
    reads: AtomicUsize,
}

impl ScriptedVerifier {
    pub(super) fn with(tokens: Vec<(&str, VerifiedTransaction)>) -> Arc<Self> {
        Arc::new(Self {
            transactions: tokens
                .into_iter()
                .map(|(token, transaction)| (token.to_owned(), transaction))
                .collect(),
            reads: AtomicUsize::new(0),
        })
    }

    pub(super) fn reads(&self) -> usize {
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

/// Signing dates advance a second per fixture built. `Utc::now()` would be
/// correct in principle and flaky in practice: two fixtures constructed in one
/// expression can land in the same microsecond, at which point the server's
/// `<` correctly refuses the second as not newer — perhaps one run in ten. A
/// counter makes "built later" and "signed later" the same fact.
static FIXTURE_SEQUENCE: AtomicI64 = AtomicI64::new(0);

/// One purchase, signed after every fixture built before it.
pub(super) fn subscription(
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
pub(super) fn subscription_period(
    transaction_id: &str,
    original_transaction_id: &str,
    tier: SubscriptionTier,
    expires_in: Duration,
) -> VerifiedTransaction {
    let sequence = FIXTURE_SEQUENCE.fetch_add(1, Ordering::Relaxed);

    VerifiedTransaction {
        // Production, because these fixtures stand in for real purchases. The
        // sandbox arm is exercised where it belongs, against the real payload
        // parser in `verifier::appstore`.
        environment: StoreEnvironment::Production,
        transaction_id: transaction_id.to_owned(),
        original_transaction_id: original_transaction_id.to_owned(),
        tier,
        expires_at: Utc::now() + expires_in,
        signed_at: Utc::now() + Duration::seconds(sequence),
        revoked_at: None,
    }
}

/// The subscription most tests want: a month of Plus.
pub(super) fn plus(original_transaction_id: &str) -> VerifiedTransaction {
    subscription(original_transaction_id, SubscriptionTier::Plus, MONTH)
}

/// A refund, signed after the purchase it revokes — which is both what Apple
/// sends and what the ordering rule requires to let it through.
pub(super) fn refund(original_transaction_id: &str) -> VerifiedTransaction {
    refund_period(original_transaction_id, original_transaction_id)
}

/// A refund for one named period, signed after fixtures built before it.
pub(super) fn refund_period(
    transaction_id: &str,
    original_transaction_id: &str,
) -> VerifiedTransaction {
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
pub(super) fn apple_account_of(user: &str) -> String {
    format!("001234.{user}.0001")
}

/// The session credential the identity `user` proves itself with once
/// [`given_signed_in`] has minted one. Derived from the id rather than
/// returned from the write, so every helper needs nothing but the id it
/// already has. Unique per identity, which `user_sessions` requires — the
/// hash is its primary key.
pub(super) fn credential_of(user: &str) -> String {
    format!("{user}-session-credential")
}

/// The headers a client sends for `user` — always both, including for callers
/// this suite never signs in. That is what a real client does: it sends
/// whatever it is holding, and an unbound row is refused nothing whatever the
/// request carries.
pub(super) fn headers<'a>(user: &'a str, credential: &'a str) -> [(&'a str, &'a str); 2] {
    [
        (USER_ID_HEADER, user),
        (SESSION_CREDENTIAL_HEADER, credential),
    ]
}

/// Puts a caller in the state a verified `SignInWithApple` leaves them in:
/// bound to an Apple account, holding one live credential. Not a precondition
/// of buying — a submission asks nothing about an Apple account — but
/// `delete_account` needs it, and a bound row is the stricter setup. Written
/// straight into the two tables: how somebody signed in is the account suite's question.
pub(super) async fn given_signed_in(pool: &PgPool, user: &str) {
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

pub(super) async fn try_submit(
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

pub(super) async fn submit(app: Router, user: &str, token: &str) -> pb::Entitlement {
    try_submit(app, user, token)
        .await
        .into_ok()
        .entitlement
        .expect("every response carries an entitlement")
}

/// Erases the caller, as the account feature's own suite does — the thing a
/// revocation has to survive is a deletion, and the wire is the only way to
/// know the two features agree. Builds its own router because the caller is
/// bound (by [`given_signed_in`]), so erasing it needs an identity verifier
/// that accepts a token whose `sub` is that binding.
pub(super) async fn delete_account(db: &TestDatabase, user: &str) -> i32 {
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

pub(super) async fn read(app: Router, user: &str) -> pb::Entitlement {
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
pub(super) async fn recommend(
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
