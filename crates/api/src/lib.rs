//! The önd API. Serves gRPC-Web (the domain API, consumed by the iOS client)
//! and a small JSON surface (`/health`, `/about`) from one router on one port.
//! Everything except process startup lives here rather than in `main.rs` so
//! `tests/e2e` can drive the exact router the binary serves — a harness that
//! assembled its own router would verify a stack no deployment runs.

mod features;
mod grpc;

/// The assistant's model seam — a dependency the composition root chooses. A
/// named re-export rather than making `features` public: publishing the whole
/// feature tree would also publish every service, repository, and error type,
/// the backdoor docs/code-structure.md rules out. Adding to this list is a
/// visible decision.
pub mod assistant {
    pub use crate::features::assistant::model::bedrock::BedrockClient;
    pub use crate::features::assistant::model::breaker::GuardedModelClient;
    pub use crate::features::assistant::model::disabled::DisabledModelClient;
    pub use crate::features::assistant::model::{
        AssistantMode, ChatRole, ChatTurn, ModelChunk, ModelClient, ModelError, ModelRequest,
        ModelStream, ToolSpec, install,
    };
    pub use crate::features::assistant::types::daily_model_calls;
}

/// The journey feature's practice snapshot, published on the same terms as
/// `assistant`. No RPC serves it — it is prompt input for the assistant — so
/// `tests/e2e` has to name it here to drive the aggregates over real inserts;
/// the window and top-`N` behaviours live in SQL, which no unit test can reach.
pub mod journey {
    pub use crate::features::journey::bolt::types::BoltSnapshot;
    pub use crate::features::journey::sessions::service::practice_snapshot;
    pub use crate::features::journey::sessions::types::{
        MAX_SNAPSHOT_TECHNIQUES, PRACTICE_WINDOW_DAYS, PracticeSnapshot, TechniquePractice,
    };
}

/// The App Store signature seam, published on the same terms as `assistant`.
///
/// `Tier` travels with it because the allowance is a function of one, so a test
/// asking how many calls a subscriber gets has to be able to name it.
pub mod entitlement {
    pub use crate::features::entitlement::types::{SubscriptionTier, Tier};
    pub use crate::features::entitlement::verifier::{
        AppStoreVerifier, StoreEnvironment, TransactionVerifier, VerificationError,
        VerifiedTransaction,
    };
}

/// The Sign in with Apple seam, published on the same terms as `assistant`.
///
/// `VerifiedIdentity` travels with it because a test double has to return one,
/// and the error type because a double has to be able to refuse.
pub mod account {
    pub use crate::features::account::AuthorizationNonceHash;
    pub use crate::features::account::verifier::{
        AppleIdentityVerifier, IdentityTokenVerifier, VerificationError, VerifiedIdentity,
    };
}

pub mod config;
pub mod http;
pub mod identity;
mod jws;
pub mod obs;
pub mod proto;
pub mod state;
pub mod throttle;
mod wire;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use axum::Router;
use axum::http::StatusCode;
use tower_http::cors::{Any, CorsLayer};
use tower_http::timeout::TimeoutLayer;

use crate::state::AppState;

/// How long a scrape may take before this side gives up. Under Prometheus'
/// ten-second `scrape_timeout` on purpose, so the failure belongs to the
/// handler and leaves a record here; above `entitlement::metrics::CENSUS_BUDGET`
/// so the gauge that can hang gives up before the handler does and the rest of
/// the exposition still renders.
const SCRAPE_TIMEOUT: Duration = Duration::from_secs(5);

/// Assembles the one router that answers both protocols.
///
/// gRPC paths are `/ond.v1.<Service>/<Method>` and can never collide with
/// the JSON routes (`/health`, `/about`), so HTTP matches first and anything
/// unmatched falls through to gRPC.
pub fn build_app(state: Arc<AppState>) -> Result<Router> {
    let cors = cors_layer(state.config.is_local());

    let grpc_router = grpc::build_services(&state)?
        .prepare()
        .into_axum_router()
        // Inside `GrpcWebLayer`, so it sees a plain gRPC request and its error
        // responses are re-framed as gRPC-Web on the way out. Only the gRPC
        // router carries it: `/health` must answer without a database, and an
        // identity that upserts a row is exactly the dependency that would
        // break.
        .layer(axum::middleware::from_fn_with_state(
            Arc::clone(&state),
            identity::resolve,
        ))
        // Outside the identity layer, so a caller over budget is turned away
        // before the upsert can write; inside `GrpcWebLayer`, so the refusal
        // reaches the client as a readable status. Only the gRPC router
        // carries it: `/health` tells the deploy whether the box came back,
        // and a health check that can be rationed can make a deploy look failed.
        .layer(axum::middleware::from_fn_with_state(
            Arc::clone(&state),
            throttle::enforce,
        ))
        // Still native gRPC here, and outside both refusal layers above. This
        // is the only altitude where an auth/throttle status in the response
        // head and a mid-stream status in trailers are both observable.
        .layer(axum::middleware::from_fn(obs::metrics::record_grpc))
        .layer(tonic_web::GrpcWebLayer::new());

    // Installed here rather than in `main`, so the router `tests/e2e` drives is
    // the one carrying the middleware below and `/metrics` answers in the tests
    // too. Idempotent, because every test in the suite builds an app.
    obs::metrics::install();

    // Outermost, so the one per-request record covers both protocols and every
    // rejection the layers below it produce — a CORS refusal included. Metrics
    // sit at the same altitude and for the same reason: a request turned away by
    // CORS or by the throttle is exactly the one worth seeing on a graph.
    Ok(http::router(state)
        .fallback_service(grpc_router)
        .layer(cors)
        .layer(axum::middleware::from_fn(obs::metrics::record_http))
        // Directly beneath the trace layer, and it has to stay there: it stamps a
        // marker the layer above reads off the response to pick a level, so
        // anything inserted between the two is something that could rebuild the
        // response and quietly restore the probe noise.
        .layer(axum::middleware::from_fn(obs::mark_probes))
        .layer(obs::trace_layer()))
}

/// The scrape listener's router: one route, no CORS, no identity, no throttle.
/// A second `Router` on a second port because on the public listener
/// `/metrics` would be public the moment it was added — Caddy proxies every
/// path unconditionally. Nothing publishes this port: the api service maps no
/// host port. Unauthenticated on purpose; the boundary is the network, as for `/health`.
pub fn metrics_router(state: Arc<AppState>) -> Router {
    obs::metrics::install();
    // After `install`, because the macros are silent no-ops until a recorder
    // exists — and here rather than in `main`, so the e2e suite exercises the
    // same series a deployment publishes.
    obs::metrics::describe_build(
        http::BUILD_INFO.commit,
        http::BUILD_INFO.built_at,
        state.config.environment.as_str(),
    );
    obs::metrics::describe_start_time();
    obs::metrics::describe_panics();
    obs::metrics::describe_identities();
    features::account::metrics::describe_sign_ins();

    Router::new()
        .route("/metrics", axum::routing::get(obs::exposition::render))
        // The backstop under the census's own budget, which is what actually
        // bounds the one gauge that can hang. This catches anything else that
        // might, and answers 503 rather than the default 408: a scrape that ran
        // out of time is this service failing to answer, not the scraper having
        // taken too long to ask.
        .layer(TimeoutLayer::with_status_code(
            StatusCode::SERVICE_UNAVAILABLE,
            SCRAPE_TIMEOUT,
        ))
        // The timeout's 503 is built inside this, so a scrape that gave up is
        // stamped as a probe and then goes loud anyway on the status half of the
        // rule — which is the one line on this listener worth having.
        .layer(axum::middleware::from_fn(obs::mark_probes))
        // The same access record every other route leaves. This listener had
        // none, so the one request it serves was the only one in the process
        // that could fail silently. A successful scrape now leaves it at `debug`:
        // fifteen seconds apart, it was most of this process's log volume.
        .layer(obs::trace_layer())
        .with_state(state)
}

/// gRPC-Web carries its status out-of-band in the `grpc-status` and
/// `grpc-message` headers, so a client cannot read a response — even a
/// successful one — unless those headers are explicitly exposed. Omitting them
/// produces a request that succeeds on the wire and fails in the client.
fn cors_layer(is_local: bool) -> CorsLayer {
    let layer = CorsLayer::new()
        .allow_methods(Any)
        .allow_headers(Any)
        .expose_headers([
            axum::http::HeaderName::from_static("grpc-status"),
            axum::http::HeaderName::from_static("grpc-message"),
        ]);

    if is_local {
        layer.allow_origin(Any)
    } else {
        // Deployed origins are not known yet. Refusing every cross-origin
        // request is the correct placeholder: the iOS client is not a browser
        // and sends no Origin, so this restricts nothing it needs.
        layer
    }
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::{Request, header};
    use axum::routing::get;
    use tower::ServiceExt;

    use super::*;

    /// Exposing `grpc-status`/`grpc-message` is the whole reason `cors_layer`
    /// exists (docs/transport.md): without them a gRPC-Web response succeeds on
    /// the wire and fails in the client, silently.
    #[tokio::test]
    async fn exposes_the_grpc_status_headers() {
        let app = Router::new()
            .route("/", get(|| async { "ok" }))
            .layer(cors_layer(true));

        let response = app
            .oneshot(
                Request::get("/")
                    .header(header::ORIGIN, "http://localhost:18100")
                    .body(Body::empty())
                    .expect("a valid request"),
            )
            .await
            .expect("the router is infallible");

        let exposed = response
            .headers()
            .get(header::ACCESS_CONTROL_EXPOSE_HEADERS)
            .expect("the expose-headers header is present")
            .to_str()
            .expect("header value is ASCII");
        assert!(exposed.contains("grpc-status"));
        assert!(exposed.contains("grpc-message"));
    }
}
