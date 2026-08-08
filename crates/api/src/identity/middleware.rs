//! The caller as carried on a request: the header it arrives in, the extension
//! it is injected as, and the middleware that does both.

use std::sync::Arc;

use axum::extract::{Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tonic::Status;
use uuid::Uuid;

use super::repository;
use crate::state::AppState;
use crate::{obs, throttle};

/// The header every client sends its anonymous id in.
///
/// Lowercase because gRPC metadata keys are, and a client that sends
/// `Ond-User-Id` over HTTP/2 sends an invalid header rather than a
/// mixed-case one.
pub const USER_ID_HEADER: &str = "ond-user-id";

/// The caller, placed in the request extensions for handlers to read.
///
/// A newtype rather than a bare `Uuid` so an extension lookup cannot silently
/// match some other id the request happens to be carrying.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UserId(pub Uuid);

/// Resolves the caller and guarantees their row exists.
///
/// Three outcomes, and the middle one is the point:
///
/// - **No header** — passes through untouched. `TechniqueService` is public
///   reference data, so requiring identity to read the catalogue would gate the
///   app's first screen on a Keychain write.
/// - **A malformed header** — `UNAUTHENTICATED`, on any service. A client that
///   sends something is claiming an identity, and a claim that does not parse is
///   a bug worth failing loudly rather than treating as anonymity.
/// - **A well-formed header** — upserts the row and injects [`UserId`].
///
/// The upsert happens on this path rather than in the first handler that needs
/// a user, because "first sight" is literally the first RPC, whichever one that
/// is: an app that onboards offline and only ever lists techniques still has a
/// row waiting when its profile finally syncs.
///
/// A well-formed header is a claim anybody can make, though, and a fresh one
/// each time is a `users` row each time. So creating a row is charged against
/// `throttle::Throttle::spend_new_identity`, and a caller over that budget is
/// refused *instead of* being written. Merely being an identity stays free: an
/// established client's row already exists, so the branch that spends never
/// runs for them.
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
        // The value itself is not logged: it is the caller's whole credential,
        // and a malformed one is still a value someone may retry successfully.
        tracing::warn!("rejected a request whose `{USER_ID_HEADER}` is not a UUID");
        return Status::unauthenticated(format!("`{USER_ID_HEADER}` must be a UUID")).into_http();
    };

    // Before the database work, not after: everything this request logs from
    // here on — the failures below, each feature's `From<…> for Status`, and the
    // layer's own completion line — is only attributable to a person once the
    // span carries them.
    obs::record_user_id(user_id);

    match repository::is_known(&state.pool, user_id).await {
        Err(error) => {
            tracing::error!(%error, "failed to look up the calling user");
            return Status::internal("internal error").into_http();
        }
        Ok(true) => {}
        Ok(false) => {
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

            if let Err(error) = repository::create(&state.pool, user_id).await {
                tracing::error!(%error, "failed to record the calling user");
                return Status::internal("internal error").into_http();
            }
        }
    }

    request.extensions_mut().insert(user_id);
    next.run(request).await
}

/// The caller, for a service that has nothing to answer without one.
///
/// [`resolve`] has already rejected a header it could not parse, so a missing
/// extension means no header was sent at all. Living beside the newtype rather
/// than in any one feature that calls it: six of the seven services are scoped
/// to a person, and each deciding this separately is six chances to disagree on
/// the status or the wording.
pub fn require<T>(request: &tonic::Request<T>) -> Result<UserId, Status> {
    request
        .extensions()
        .get::<UserId>()
        .copied()
        .ok_or_else(|| Status::unauthenticated(format!("`{USER_ID_HEADER}` is required")))
}
