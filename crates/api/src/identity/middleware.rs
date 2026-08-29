//! The caller as carried on a request: the header it arrives in, the extension
//! it is injected as, and the middleware that does both.

use std::fmt;
use std::sync::Arc;

use axum::extract::{Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tonic::Status;
use uuid::Uuid;

use super::credential::CredentialHash;
use super::repository;
use crate::state::AppState;
use crate::{obs, throttle};

/// The header every client sends its anonymous id in.
///
/// Lowercase because gRPC metadata keys are, and a client that sends
/// `Ond-User-Id` over HTTP/2 sends an invalid header rather than a
/// mixed-case one.
pub const USER_ID_HEADER: &str = "ond-user-id";

/// The header a signed-in client proves that id with. A header rather than a
/// request field: the id being proved already travels as a header, the check
/// belongs at the single choke point [`resolve`] is, and `AssistantService`
/// streams, where headers settle once at stream start. Not `authorization` —
/// that names a scheme this is not, and CORS, proxies and logging treat it specially.
pub const SESSION_CREDENTIAL_HEADER: &str = "ond-session-credential";

/// The caller, placed in the request extensions for handlers to read. A
/// newtype rather than a bare `Uuid` so an extension lookup cannot silently
/// match some other id the request carries; transparent to sqlx so a query
/// reads a column back as this type, closing the same hazard one row down.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(transparent)]
pub struct UserId(pub Uuid);

impl UserId {
    /// How this identity is named anywhere somebody who is not it could read
    /// it: the log stream and the person's own Settings screen. Never the id
    /// itself — possession of that is the entire claim to the account, and
    /// logs travel further than databases do. The reference still correlates a
    /// caller's requests and finds the row with `WHERE id::text LIKE 'xxxxxxxx-xxxx%'`.
    pub const fn support_reference(self) -> SupportReference {
        SupportReference(self.0)
    }
}

/// An identity as it is written down: the first two dash-separated groups of
/// the canonical lowercase form — twelve hex digits and the hyphen between
/// them. One of the rule's two definition sites; the other is
/// `AccountModel.supportReference` in the iOS app, and the two must not drift.
/// A `Display` wrapper rather than a `String` so the per-request path allocates nothing.
#[derive(Debug, Clone, Copy)]
pub struct SupportReference(Uuid);

impl fmt::Display for SupportReference {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        const GROUPS: usize = 13;

        let mut buffer = Uuid::encode_buffer();

        formatter.write_str(&self.0.hyphenated().encode_lower(&mut buffer)[..GROUPS])
    }
}

/// Resolves the caller, proves their claim to that identity, and guarantees their row exists.
///
/// Five outcomes, from a missing header that passes through to an upsert that injects [`UserId`].
/// Each one, the anonymous path they leave untouched, and the throttle that prices a new row are
/// "Resolving the caller" in `docs/architecture.md`.
pub async fn resolve(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let Some(header) = request.headers().get(USER_ID_HEADER) else {
        return next.run(request).await;
    };

    let Some(user_id) = header
        .to_str()
        .ok()
        .and_then(|value| Uuid::parse_str(value).ok())
        .map(UserId)
    else {
        // The value is not logged — it is the caller's whole credential.
        // `debug`, like every refusal below: a scanner or one bad client build
        // would otherwise stream warnings no human should act on. Still
        // counted — `record_grpc` sits outside this layer, so it lands as
        // ond_grpc_requests_total with status 16.
        tracing::debug!("rejected a request whose `{USER_ID_HEADER}` is not a UUID");
        return Status::unauthenticated(format!("`{USER_ID_HEADER}` must be a UUID")).into_http();
    };

    // Before the database work, not after: everything this request logs from
    // here on — the failures below, each feature's `From<…> for Status`, and the
    // layer's own completion line — is only attributable to a person once the
    // span carries them.
    obs::record_user_id(user_id);

    let presented = request
        .headers()
        .get(SESSION_CREDENTIAL_HEADER)
        .and_then(|value| value.to_str().ok())
        .map(CredentialHash::of);

    match repository::standing(&state.pool, user_id, presented.as_ref()).await {
        Err(error) => {
            tracing::error!(%error, "failed to look up the calling user");
            return Status::internal("internal error").into_http();
        }
        Ok(Some(standing)) => {
            if standing == repository::Standing::BoundUncredentialed {
                // `debug` rather than `warn`: a reinstall that kept the id and
                // lost the Keychain produces this on an honest launch, and the
                // level should not imply an attack every time somebody restores
                // a backup.
                tracing::debug!(
                    "refused a signed-in identity presenting no valid session credential"
                );
                return Status::unauthenticated(format!(
                    "`{SESSION_CREDENTIAL_HEADER}` is required for this identity"
                ))
                .into_http();
            }
        }
        Ok(None) => {
            let merged = match repository::merged_away(&state.pool, user_id).await {
                Ok(merged) => merged,
                Err(error) => {
                    tracing::error!(%error, "failed to check whether the caller was merged away");
                    return Status::internal("internal error").into_http();
                }
            };

            if merged {
                // `debug` for the reason the bound-row refusal above is: an
                // honest watch sync produces this until the handoff lands.
                tracing::debug!("refused an identity that was merged into an account");
                return Status::unauthenticated(format!(
                    "`{USER_ID_HEADER}` names an identity that was merged into an account; \
                     send the adopted id"
                ))
                .into_http();
            }

            if !state
                .throttle
                .spend_new_identity(throttle::client_key(request.headers()))
            {
                // `debug` for the reason `throttle::enforce`'s refusal is: this
                // is one line per refused request, and the budget it belongs to
                // has already warned once, in the window it was filled.
                tracing::debug!("refused a request creating an identity over its rate limit");
                return throttle::refused();
            }

            match repository::create(&state.pool, user_id).await {
                // Counted rather than logged. "Did anyone new arrive today" is a
                // rate, and a line per new person is a line that stops being
                // readable at exactly the point the answer starts being good news.
                // `ond_users_total` is a once-a-minute gauge whose flatness cannot
                // be told apart from a quiet week; this can.
                Ok(repository::Created::Row) => obs::metrics::identity_created(),
                Ok(repository::Created::AlreadyExisted) => {}
                Err(error) => {
                    tracing::error!(%error, "failed to record the calling user");
                    return Status::internal("internal error").into_http();
                }
            }
        }
    }

    request.extensions_mut().insert(user_id);
    next.run(request).await
}

/// The caller, for a service that has nothing to answer without one.
/// [`resolve`] has already rejected a header it could not parse, so a missing
/// extension means no header was sent at all. Living beside the newtype
/// because each feature deciding this separately is a chance to disagree on
/// the status or the wording.
pub fn require<T>(request: &tonic::Request<T>) -> Result<UserId, Status> {
    request
        .extensions()
        .get::<UserId>()
        .copied()
        .ok_or_else(|| Status::unauthenticated(format!("`{USER_ID_HEADER}` is required")))
}

/// The credential the caller presented, hashed — for the one RPC whose job is
/// to revoke it. Read straight from the metadata: an extension copy would be a
/// second place to read the same value, with nothing keeping the two in
/// agreement. [`resolve`] has already refused any *bound* caller without a
/// live credential, so `None` here is a person with nothing to revoke, not a skipped check.
pub fn presented_credential<T>(request: &tonic::Request<T>) -> Option<CredentialHash> {
    request
        .metadata()
        .get(SESSION_CREDENTIAL_HEADER)
        .and_then(|value| value.to_str().ok())
        .map(CredentialHash::of)
}
