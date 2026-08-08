//! Business logic — turns a proven Apple account into the identity the device
//! should carry from now on, and erases one on request.
//!
//! Receives explicit dependencies (`&PgPool`, `&dyn IdentityTokenVerifier`),
//! never `Arc<AppState>`, and contains zero raw queries.

use sqlx::PgPool;

use super::errors::AccountError;
use super::repository;
use super::verifier::IdentityTokenVerifier;
use crate::identity::{self, CredentialHash, UserId};
use crate::proto::ond::v1 as pb;

/// Verifies the identity token, binds the Apple account it names, and mints the
/// credential that identity will prove itself with from now on.
///
/// The response's id is half the point of the call: it is the caller's own on a
/// first sign-in and an older identity when this Apple account already had one,
/// and the client persists it either way. What decides which — and what happens
/// to the caller's history in the second case — is
/// `repository::bind_apple_account`.
///
/// The credential is the other half, and it is minted here rather than inside
/// that transaction on purpose. Binding and minting are separate writes, so a
/// failure between them leaves a row that is bound with no credential handed
/// out — a caller who is refused everything until they sign in again, which they
/// can, because `bind_apple_account` answers a caller who already holds the
/// account with its own id. The opposite order is the one that cannot be
/// recovered from: a credential in a client's Keychain that no binding backs.
pub async fn sign_in_with_apple(
    pool: &PgPool,
    verifier: &dyn IdentityTokenVerifier,
    caller: UserId,
    identity_token: &str,
) -> Result<pb::SignInWithAppleResponse, AccountError> {
    let identity = verifier.verify(identity_token).await?;
    let adopted = repository::bind_apple_account(pool, caller, &identity.apple_user_id).await?;
    let credential = identity::start_session(pool, UserId(adopted)).await?;

    if adopted != caller.0 {
        // One identity ceasing to exist and another absorbing its history is the
        // only destructive thing this server does on a client's say-so, and this
        // line is the only account of it. The Apple id is deliberately absent:
        // it is the credential the whole binding rests on, and neither id here
        // is useful without it. Both identities by reference, for the reason
        // `UserId::support_reference` gives.
        tracing::info!(
            feature = "account",
            from = %caller.support_reference(),
            to = %UserId(adopted).support_reference(),
            "merged an anonymous identity into a signed-in one"
        );
    }

    Ok(pb::SignInWithAppleResponse {
        user_id: adopted.to_string(),
        session_credential: credential.into_secret(),
    })
}

/// Revokes the credential this request was made with.
///
/// Only that one. A person signed in on two devices signs out of one of them,
/// and the other is not a device this call knows anything about.
///
/// A caller with no credential is answered `OK` having done nothing: they are
/// anonymous, so there was never anything to revoke, and a client clearing its
/// own state should not have to ask the server's permission first. `resolve` has
/// already refused any bound caller who could not prove themselves, so this
/// cannot be a signed-in person quietly skipping the revocation.
///
/// Not logged. Unlike the merge and the erasure below it, nothing is destroyed
/// that anybody could later ask about — the identity, its history and its
/// binding are all exactly as they were.
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

/// Erases the caller and everything filed under them, once they have proved they
/// may.
///
/// What proof is required depends on what the row carries, and the asymmetry is
/// the one `bind_apple_account` already enforces on the way in: possession of an
/// anonymous id is not a credential that may be weighed against a signed-in one.
/// A row with an `apple_user_id` therefore has to present a fresh identity token
/// whose `sub` is that binding, and a row without one is erased on the header
/// alone — for a row with nothing stronger attached, the header genuinely is the
/// whole of the claim, and demanding more would put erasure out of reach of the
/// majority of people, who never sign in.
///
/// The token is verified through the same seam a sign-in goes through, so
/// "verified" means one thing in both directions: Apple signed it, for this app,
/// and it has not expired. Apple's ten-minute expiry is what makes it *fresh* —
/// a client cannot keep the one it signed in with.
///
/// Logged at `info` for the same reason the merge above is: this is the second
/// of the two destructive things the server does on a client's say-so, and the
/// row it names will not exist afterwards to be asked about. The id is not
/// repeated here — `identity::resolve` has already put its reference on the
/// span, and what was erased is by definition not something to write down on the
/// way past.
pub async fn delete_account(
    pool: &PgPool,
    verifier: &dyn IdentityTokenVerifier,
    caller: UserId,
    identity_token: &str,
) -> Result<pb::DeleteAccountResponse, AccountError> {
    let bound_to = repository::apple_account_of(pool, caller).await?;

    if let Some(bound_to) = bound_to.as_deref() {
        if identity_token.is_empty() {
            return Err(AccountError::CredentialRequired);
        }

        if verifier.verify(identity_token).await?.apple_user_id != bound_to {
            return Err(AccountError::WrongAccount);
        }
    }

    // What was proved rather than what will be found: verifying reaches Apple,
    // so the read above cannot be held under a lock, and the erasure re-checks
    // the binding against this before it commits.
    repository::delete_account(pool, caller, bound_to.as_deref()).await?;

    tracing::info!(
        feature = "account",
        "erased an account at its owner's request"
    );

    Ok(pb::DeleteAccountResponse {})
}
