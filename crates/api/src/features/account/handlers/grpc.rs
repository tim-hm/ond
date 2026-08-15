//! `AccountService` gRPC implementation.

use std::sync::Arc;

use tonic::{Request, Response, Status};

use crate::features::account::authorization::AuthorizationPurpose;
use crate::features::account::service;
use crate::identity;
use crate::proto::ond::v1::account_service_server::AccountService;
use crate::proto::ond::v1::{
    AppleAuthorizationPurpose, BeginAppleAuthorizationRequest, BeginAppleAuthorizationResponse,
    DeleteAccountRequest, DeleteAccountResponse, SignInWithAppleRequest, SignInWithAppleResponse,
    SignOutRequest, SignOutResponse,
};
use crate::state::AppState;

/// The `AccountService` transport, holding the shared state its RPCs read the
/// pool and the Sign in with Apple verifier out of.
///
/// One verifier per process rather than one per sign-in, and here the sharing is
/// load-bearing rather than merely tidy: the real verifier caches Apple's
/// published signing keys, so a fresh instance per request would fetch them from
/// Apple again every time somebody signed in.
pub struct AccountServiceImpl {
    state: Arc<AppState>,
}

impl AccountServiceImpl {
    pub const fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

/// Scoped to one person exactly as every other service is: the anonymous
/// identity travels in the `ond-user-id` header, and there is nothing to answer a
/// caller without one — a sign-in with no identity to bind would have to mint a
/// row the client never asked for.
#[tonic::async_trait]
impl AccountService for AccountServiceImpl {
    async fn begin_apple_authorization(
        &self,
        request: Request<BeginAppleAuthorizationRequest>,
    ) -> Result<Response<BeginAppleAuthorizationResponse>, Status> {
        let user_id = identity::require(&request)?;
        let purpose = match AppleAuthorizationPurpose::try_from(request.into_inner().purpose) {
            Ok(AppleAuthorizationPurpose::SignIn) => AuthorizationPurpose::SignIn,
            Ok(AppleAuthorizationPurpose::DeleteAccount) => AuthorizationPurpose::DeleteAccount,
            Ok(AppleAuthorizationPurpose::Unspecified) | Err(_) => {
                return Err(crate::features::account::errors::AccountError::InvalidPurpose.into());
            }
        };

        let response =
            service::begin_apple_authorization(&self.state.pool, user_id, purpose).await?;

        Ok(Response::new(response))
    }

    async fn sign_in_with_apple(
        &self,
        request: Request<SignInWithAppleRequest>,
    ) -> Result<Response<SignInWithAppleResponse>, Status> {
        let user_id = identity::require(&request)?;
        let identity_token = request.into_inner().identity_token;

        let response = service::sign_in_with_apple(
            &self.state.pool,
            self.state.account.as_ref(),
            user_id,
            &identity_token,
        )
        .await?;

        Ok(Response::new(response))
    }

    /// The one RPC that reads a header rather than its request message: what it
    /// revokes is the credential the caller proved themselves with, and that
    /// arrives in `ond-session-credential` like it does on every other call.
    /// Taking it as a field would let a client revoke a credential it is not
    /// currently using, which is not a thing signing out means.
    async fn sign_out(
        &self,
        request: Request<SignOutRequest>,
    ) -> Result<Response<SignOutResponse>, Status> {
        let user_id = identity::require(&request)?;
        let credential = identity::presented_credential(&request);

        let response = service::sign_out(&self.state.pool, user_id, credential.as_ref()).await?;

        Ok(Response::new(response))
    }

    /// Requires an identity for the reason the sign-in does, turned around: with
    /// no header there is nothing to erase, and a call that answered `OK` to one
    /// would tell somebody their account is gone having touched nothing.
    ///
    /// Reads the same verifier the sign-in does, because an Apple-bound identity
    /// has to prove itself before the one irreversible operation in the API —
    /// which of the two credentials is enough is `service::delete_account`'s
    /// decision, taken from the row rather than from the request.
    async fn delete_account(
        &self,
        request: Request<DeleteAccountRequest>,
    ) -> Result<Response<DeleteAccountResponse>, Status> {
        let user_id = identity::require(&request)?;
        let identity_token = request.into_inner().identity_token;

        let response = service::delete_account(
            &self.state.pool,
            self.state.account.as_ref(),
            user_id,
            &identity_token,
        )
        .await?;

        Ok(Response::new(response))
    }
}
