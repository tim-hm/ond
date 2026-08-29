//! Business logic — turns a proven Apple account into the identity the device
//! should carry from now on, and erases one on request.
//!
//! Receives explicit dependencies (`&PgPool`, `&dyn IdentityTokenVerifier`),
//! never `Arc<AppState>`, and contains zero raw queries.

use sqlx::PgPool;

use super::authorization::{AuthorizationChallenge, AuthorizationPurpose};
use super::errors::AccountError;
use super::metrics;
use super::repository;
use super::verifier::IdentityTokenVerifier;
use crate::identity::{self, CredentialHash, UserId};
use crate::proto::ond::v1 as pb;

const MAX_IDENTITY_TOKEN_BYTES: usize = 8 * 1024;

/// Mints and stores the caller- and purpose-bound ceremony Apple will sign into
/// the next identity token.
pub async fn begin_apple_authorization(
    pool: &PgPool,
    caller: UserId,
    purpose: AuthorizationPurpose,
) -> Result<pb::BeginAppleAuthorizationResponse, AccountError> {
    let challenge = AuthorizationChallenge::mint()?;
    repository::begin_authorization(pool, caller, purpose, &challenge).await?;

    Ok(pb::BeginAppleAuthorizationResponse {
        expires_at: Some(crate::wire::timestamp_to_proto(challenge.expires_at())),
        nonce: challenge.into_raw(),
    })
}

/// Verifies the identity token, binds the Apple account it names, and mints
/// the credential the identity proves itself with from now on. The returned
/// id is the caller's own on a first sign-in, an older identity when the
/// account already had one. `repository::sign_in` decides which atomically, so
/// a failed transaction leaves neither a partial binding nor a live credential.
pub async fn sign_in_with_apple(
    pool: &PgPool,
    verifier: &dyn IdentityTokenVerifier,
    caller: UserId,
    identity_token: &str,
) -> Result<pb::SignInWithAppleResponse, AccountError> {
    reject_oversized_token(identity_token)?;
    let identity = verifier.verify(identity_token).await?;
    let (adopted, outcome, credential) = repository::sign_in(
        pool,
        caller,
        &identity.apple_user_id,
        &identity.authorization_nonce,
    )
    .await?;

    metrics::sign_in(outcome);

    if outcome == metrics::SignIn::Merged {
        // A merge is destructive, and this line is its only account. The Apple
        // id is deliberately absent — it is the credential the whole binding
        // rests on. Both identities by reference, for the reason
        // `UserId::support_reference` gives.
        tracing::info!(
            feature = "account",
            from = %caller.support_reference(),
            to = %adopted.support_reference(),
            "merged an anonymous identity into a signed-in one"
        );
    }

    Ok(pb::SignInWithAppleResponse {
        user_id: adopted.0.to_string(),
        session_credential: credential.into_secret(),
    })
}

/// Revokes the credential this request was made with — only that one; a
/// person's other devices are not this call's business. A caller with no
/// credential is answered `OK` having done nothing: they are anonymous, and
/// `resolve` has already refused any bound caller who could not prove
/// themselves. Not logged: nothing is destroyed that anybody could ask about.
pub async fn sign_out(
    pool: &PgPool,
    caller: UserId,
    credential: Option<&CredentialHash>,
) -> Result<pb::SignOutResponse, AccountError> {
    if let Some(credential) = credential {
        identity::end_session(pool, caller, credential).await?;
    }

    Ok(pb::SignOutResponse {})
}

/// Erases the caller and everything filed under them, once they prove they
/// may. An Apple-bound row must present a fresh identity token whose `sub` is
/// the binding, its signed nonce consuming a deletion-only server challenge —
/// a token kept from sign-in does not work. An unbound row is erased on the
/// header alone: there the header is the whole claim, and most never sign in.
pub async fn delete_account(
    pool: &PgPool,
    verifier: &dyn IdentityTokenVerifier,
    caller: UserId,
    identity_token: &str,
) -> Result<pb::DeleteAccountResponse, AccountError> {
    reject_oversized_token(identity_token)?;
    let bound_to = repository::apple_account_of(pool, caller).await?;

    let authorization_nonce = if let Some(bound_to) = bound_to.as_deref() {
        if identity_token.is_empty() {
            return Err(AccountError::CredentialRequired);
        }

        let identity = verifier.verify(identity_token).await?;
        if identity.apple_user_id != bound_to {
            return Err(AccountError::WrongAccount);
        }

        Some(identity.authorization_nonce)
    } else {
        None
    };

    // What was proved rather than what will be found: verifying reaches Apple,
    // so the read above cannot be held under a lock, and the erasure re-checks
    // the binding against this before it commits.
    repository::delete_account(
        pool,
        caller,
        bound_to.as_deref(),
        authorization_nonce.as_ref(),
    )
    .await?;

    tracing::info!(
        feature = "account",
        "erased an account at its owner's request"
    );

    Ok(pb::DeleteAccountResponse {})
}

fn reject_oversized_token(identity_token: &str) -> Result<(), AccountError> {
    if identity_token.len() > MAX_IDENTITY_TOKEN_BYTES {
        return Err(AccountError::TokenTooLarge(MAX_IDENTITY_TOKEN_BYTES));
    }

    Ok(())
}
