//! Process entry point for the önd API.
//!
//! Boot order is: configuration, telemetry, database pool, router, serve. The
//! router itself is `api::build_app` so that the integration tests exercise the
//! same stack this binary serves.

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use api::account::AppleIdentityVerifier;
use api::entitlement::AppStoreVerifier;
use api::state::AppState;
use api::{assistant, config, http, obs};
use sqlx::postgres::PgPoolOptions;

/// Sized for a local machine and a small deployment. Postgres' own default
/// `max_connections` is 100, so this leaves ample room for the migrate binary
/// and a psql session alongside.
const MAX_DB_CONNECTIONS: u32 = 10;

/// How long a request waits for a connection before giving up.
///
/// sqlx's own default is thirty seconds, which on a pool this size is the wrong
/// shape of failure. Several of this crate's reads fan out concurrently, so a
/// handful of simultaneous callers can want more connections than
/// [`MAX_DB_CONNECTIONS`] between them — and half a minute of waiting turns
/// that into requests that hang and clients that retry into the queue. Three
/// seconds turns it into a fast, logged `PoolTimedOut` naming the pool as the
/// thing that ran out.
///
/// Deliberately not answered by raising `max_connections`: the number worth
/// fixing is how many connections one request holds at once, and a larger pool
/// would only move the same cliff further out while hiding it from exactly this
/// signal.
///
/// It is also the deadline sqlx gives itself to open the pool below, so it
/// bounds how long boot tolerates a server that is up but still recovering.
/// Three seconds is enough because nothing here races the server's first boot:
/// `mise run dev:db` waits on the container's `pg_isready` healthcheck, and the
/// deployment's compose file waits on the same one.
const DB_ACQUIRE_TIMEOUT: Duration = Duration::from_secs(3);

#[tokio::main]
async fn main() -> Result<()> {
    let config = config::load()?;
    obs::init(config.wants_json_logs());

    tracing::info!(
        commit = http::BUILD_INFO.commit,
        built_at = http::BUILD_INFO.built_at,
        environment = ?config.environment,
        "starting ond api",
    );

    let pool = PgPoolOptions::new()
        .max_connections(MAX_DB_CONNECTIONS)
        .acquire_timeout(DB_ACQUIRE_TIMEOUT)
        // Keeps one connection warm. Without it, the first request after an idle
        // period pays full TCP, TLS, and Postgres auth — which on a low-traffic
        // service is most requests.
        .min_connections(1)
        .connect(&config.database_url)
        .await
        .context("failed to connect to the database — is `mise run dev:db` running?")?;
    tracing::info!("connected to the database");

    // The composition root's one real choice: which side of the assistant's
    // model seam this process runs. Decided by whether AWS credentials resolve,
    // and logged there either way — at `warn` in a deployment, where failing to
    // resolve them means the coach is down rather than absent.
    let assistant = assistant::install(config.environment).await;

    // No equivalent choice for either Apple seam: the App Store's trust anchor
    // is compiled in and Sign in with Apple's keys are fetched from a fixed
    // endpoint, so every environment runs the same two verifiers and there is no
    // configuration that could relax either. The identity verifier is built
    // rather than named because it owns an HTTP client, and a process whose TLS
    // stack will not initialise cannot reach Postgres either — so the failure is
    // fatal rather than something to degrade around.
    let account =
        AppleIdentityVerifier::new().context("failed to build the Apple identity verifier")?;

    let state = AppState::new(
        pool,
        config,
        assistant,
        Arc::new(AppStoreVerifier),
        Arc::new(account),
    );
    let port = state.config.port;
    let metrics_port = state.config.metrics_port;

    // Bound before the public listener and on its own socket, so a process that
    // cannot serve its scrape target fails at boot rather than presenting a
    // silently unmonitored deployment. `0.0.0.0` inside the container is not
    // exposure: the api service publishes no host port, so this reaches the
    // compose network and stops there.
    let metrics_listener = tokio::net::TcpListener::bind(("0.0.0.0", metrics_port))
        .await
        .with_context(|| format!("failed to bind the metrics port {metrics_port}"))?;
    let metrics = api::metrics_router(Arc::clone(&state));
    tracing::info!(port = metrics_port, "serving metrics");

    // Detached rather than sharing the graceful shutdown below. A scrape holds
    // no client work worth draining, and making the public listener's drain wait
    // on Prometheus's next connection would turn a routine restart into a
    // fifteen-second one.
    tokio::spawn(async move {
        if let Err(error) = axum::serve(metrics_listener, metrics).await {
            tracing::error!(%error, "the metrics listener stopped");
        }
    });

    let app = api::build_app(state)?;

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .with_context(|| format!("failed to bind port {port}"))?;
    tracing::info!(port, "listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("server terminated unexpectedly")?;

    Ok(())
}

/// Resolves when the process is asked to stop: SIGINT (^C in a terminal) or
/// SIGTERM (what container runtimes and supervisors send first). Handing this
/// to `with_graceful_shutdown` lets in-flight requests drain instead of being
/// severed mid-response.
///
/// A handler that fails to install logs and parks forever rather than
/// panicking — the other signal (or SIGKILL) still ends the process.
async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(%error, "failed to install the SIGINT handler");
            std::future::pending::<()>().await;
        }
    };

    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(error) => {
                tracing::error!(%error, "failed to install the SIGTERM handler");
                std::future::pending::<()>().await;
            }
        }
    };

    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }

    tracing::info!("shutdown signal received, draining in-flight requests");
}
