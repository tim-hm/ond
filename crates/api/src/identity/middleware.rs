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

/// The header a signed-in client proves that id with.
///
/// Beside [`USER_ID_HEADER`] rather than inside a request message, for three
/// reasons: the thing being proved already travels as a header, so splitting a
/// credential from its proof across two transports would be the odd choice; the
/// check belongs at the single choke point [`resolve`] is, rather than in six
/// services' handlers where a new RPC defaults to passing; and `AssistantService`
/// streams, where headers are settled once at stream start and "a field on every
/// message" is not even well defined.
///
/// Not `authorization`. That header means a scheme this is not, and CORS,
/// proxies and logging middleware all treat it specially — an `ond-` header sits
/// beside the id it proves and is described in the same leading comments.
pub const SESSION_CREDENTIAL_HEADER: &str = "ond-session-credential";

/// The caller, placed in the request extensions for handlers to read.
///
/// A newtype rather than a bare `Uuid` so an extension lookup cannot silently
/// match some other id the request happens to be carrying.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UserId(pub Uuid);

impl UserId {
    /// How this identity is named anywhere it could be read by somebody who is
    /// not it: the log stream, and the person's own Settings screen.
    ///
    /// Never the id itself. Possession of that is the entire claim to the
    /// account — reading and rewriting the profile, spending the assistant's
    /// allowance, and `DeleteAccount` — so a log line carrying it verbatim is an
    /// account key, and logs travel further than databases do. Attribution does
    /// not need the spendable form: the reference still correlates one caller's
    /// requests to each other and still finds the row with
    /// `WHERE id::text LIKE 'xxxxxxxx-xxxx%'`.
    ///
    /// Here rather than in `obs` because it is a fact about an identity rather
    /// than about logging, and three places want it: the request span, the two
    /// service audit lines, and — by the same derivation in the other language —
    /// the app.
    pub const fn support_reference(self) -> SupportReference {
        SupportReference(self.0)
    }
}

/// An identity as it is written down, and the derivation rule itself.
///
/// **One of the rule's two definition sites.** The other is
/// `AccountModel.supportReference` in the iOS app, which shows the person the
/// same twelve hex characters as their "Support ID" — a reference somebody
/// quotes and an operator greps have to be one string, so the two must not
/// drift apart.
///
/// The rule: the first two dash-separated groups of the canonical lowercase
/// form, which is twelve hex digits and the hyphen between them.
///
/// A `Display` wrapper rather than a `String`, so the one path that runs on
/// every request formats straight into the subscriber's buffer and allocates
/// nothing.
#[derive(Debug, Clone, Copy)]
pub struct SupportReference(Uuid);

impl fmt::Display for SupportReference {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        const GROUPS: usize = 13;

        let mut buffer = Uuid::encode_buffer();

        formatter.write_str(&self.0.hyphenated().encode_lower(&mut buffer)[..GROUPS])
    }
}

/// Resolves the caller, proves they are entitled to the identity they claim, and
/// guarantees their row exists.
///
/// Four outcomes:
///
/// - **No header** — passes through untouched. `TechniqueService` is public
///   reference data, so requiring identity to read the catalogue would gate the
///   app's first screen on a Keychain write.
/// - **A malformed header** — `UNAUTHENTICATED`, on any service. A client that
///   sends something is claiming an identity, and a claim that does not parse is
///   a bug worth failing loudly rather than treating as anonymity.
/// - **A well-formed header naming a row bound to an Apple account**, with no
///   credential proving that binding — `UNAUTHENTICATED`, before any handler
///   runs. Possession of the id is what this used to accept, and a bound row is
///   a history somebody can be handed back on another device — worth more than
///   the bare id that names it.
/// - **Anything else** — upserts the row and injects [`UserId`].
///
/// **The anonymous path is unchanged.** A row with no `apple_user_id` has
/// nothing to prove, is asked for nothing, and is refused nothing — local-only
/// mode is the majority of people and is not an account to be locked out of.
///
/// The rule is *once bound, always prove*, and it applies to `SignInWithApple`
/// like everything else. A client that has lost its credential but kept a bound
/// id is not stranded: the route back is the one a new device already takes —
/// mint a fresh anonymous id and sign in on that, which hands the bound identity
/// back along with a new credential.
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
            if standing.bound && !standing.credentialed {
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

/// The credential the caller presented, hashed — for the one RPC whose job is to
/// revoke it.
///
/// Read straight from the metadata rather than carried down in an extension:
/// the header is still on the request when the handler runs, and copying it into
/// an extension would be a second place for the same value to be read from, with
/// nothing keeping the two in agreement.
///
/// `None` for a caller who presented nothing, which is every anonymous one.
/// [`resolve`] has already refused any *bound* caller who reaches a handler
/// without a live credential, so a `None` here is a person with nothing to
/// revoke rather than a check that was skipped.
pub fn presented_credential<T>(request: &tonic::Request<T>) -> Option<CredentialHash> {
    request
        .metadata()
        .get(SESSION_CREDENTIAL_HEADER)
        .and_then(|value| value.to_str().ok())
        .map(CredentialHash::of)
}
