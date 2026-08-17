//! Process entry point for the önd API.
//!
//! Boot order is: configuration, telemetry, database pool, router, serve. The
//! router itself is `api::build_app` so that the integration tests exercise the
//! same stack this binary serves.

use std::process::ExitCode;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use api::account::AppleIdentityVerifier;
use api::config::Environment;
use api::entitlement::AppStoreVerifier;
use api::state::AppState;
use api::{assistant, config, http, obs};
use sqlx::ConnectOptions;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};

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

/// How long any one statement may run before Postgres cancels it.
///
/// [`DB_ACQUIRE_TIMEOUT`] bounds waiting *for* a connection; nothing bounded
/// what a request did once it held one. On a pool of [`MAX_DB_CONNECTIONS`],
/// ten slow statements are the whole pool, and every later caller then fails on
/// acquire — which reports the pool as the problem and says nothing about the
/// query that actually caused it.
///
/// Set here rather than as an HTTP-layer timeout on purpose. A blanket
/// `tower_http` timeout would also cut the assistant's streamed reply, which is
/// long by design and already carries its own idle deadline; the thing that
/// needs a ceiling is a statement, so the ceiling belongs on the statement.
/// Postgres cancels it server-side and sqlx surfaces it as a query error naming
/// the statement, which is the legible failure the acquire timeout cannot give.
///
/// Fifteen seconds is far above anything this schema serves — the slowest read
/// is the leaderboard, and it is a snapshot lookup since TIM-49 — so reaching
/// it means something is wrong rather than merely busy.
///
/// Deliberately this process only. `crates/migrate` opens its own pool and must
/// not inherit it: an index build on a table that has grown is exactly the long
/// statement this cancels, and cancelling it would fail a deployment rather than
/// protect one. That is also why it is set here rather than in `DATABASE_URL` or
/// on the role — both would reach migrate without anyone noticing.
const STATEMENT_TIMEOUT: &str = "15s";

/// When sqlx starts calling a statement slow, and therefore worth a `warn`
/// carrying its SQL.
///
/// Pinned rather than inherited. sqlx's own default is one second, and an
/// inherited default is a production log volume that can change under us on a
/// dependency bump with nobody deciding to change it — the same objection
/// docs/observability.md's field conventions make to anything about the log
/// stream being decided somewhere other than in this repository.
///
/// Two seconds, set against [`STATEMENT_TIMEOUT`] rather than picked in the
/// abstract: nothing this schema serves should take it, and a statement on its
/// way to being cancelled at fifteen must have warned long before. It is the
/// only thing that reports a query degrading while it is still succeeding —
/// `ond_request_duration_seconds` shows the request slowing without naming what
/// slowed it.
const SLOW_STATEMENT: Duration = Duration::from_secs(2);

/// Boots the process, and reports the reason it could not through the subscriber
/// rather than through `Termination`.
///
/// `main` returning `Result` printed every fatal boot error as `Error: …` on
/// stderr — outside the subscriber, so in production it landed in the middle of
/// a JSON stream, was shipped to Loki unparsed, and no level query could ever
/// match it. A process that will not start is the first thing anybody looks for,
/// and it was the one thing that could not be found.
#[tokio::main]
async fn main() -> ExitCode {
    // Before anything fallible, because this is what decides the format the
    // failure below is written in.
    let environment = config::environment();
    let log_filter = obs::init(environment.as_ref().is_ok_and(|env| env.wants_json_logs()));
    // After the subscriber, because the hook logs through it. Only in the
    // binary: installing a process-global hook from `build_app` would have the
    // e2e suite replace whatever the test harness had set.
    obs::metrics::install_panic_hook();

    match run(environment, log_filter).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            // `{:#}` for the whole context chain on one line: the outer message
            // says which step, the innermost says what the operating system or
            // Postgres actually refused, and a multi-line rendering would be one
            // log record per line in the aggregator.
            tracing::error!(error = format!("{error:#}"), "the api could not start");
            ExitCode::FAILURE
        }
    }
}

async fn run(environment: Result<Environment>, log_filter: String) -> Result<()> {
    // Reported here rather than at the call above so that a malformed `OND_ENV`
    // takes the same path as every other boot failure. Until it parses, the
    // format is a guess — a readable line, which is the right guess for a
    // process about to exit having served nothing.
    let config = config::load(environment?)?;

    tracing::info!(
        commit = http::BUILD_INFO.commit,
        built_at = http::BUILD_INFO.built_at,
        environment = ?config.environment,
        log_filter,
        "starting ond api",
    );

    let pool = PgPoolOptions::new()
        .max_connections(MAX_DB_CONNECTIONS)
        .acquire_timeout(DB_ACQUIRE_TIMEOUT)
        // Keeps one connection warm. Without it, the first request after an idle
        // period pays full TCP, TLS, and Postgres auth — which on a low-traffic
        // service is most requests.
        .min_connections(1)
        // In the startup packet rather than a `SET` afterwards, so it is in
        // force for the connection's first statement and costs no round trip.
        .connect_with(
            config
                .database_url
                .parse::<PgConnectOptions>()
                .context("DATABASE_URL is not a valid Postgres connection string")?
                .options([("statement_timeout", STATEMENT_TIMEOUT)])
                .log_slow_statements(log::LevelFilter::Warn, SLOW_STATEMENT),
        )
        .await
        .context("failed to connect to the database — is `mise run dev:db` running?")?;
    // Named, because "connected" alone cannot answer the question this line gets
    // asked: *which* database. A first-boot drift on the box once had every
    // nightly backup dumping the wrong one for over a week, and nothing in the
    // logs contradicted it. `redacted` is what makes the connection string
    // printable — the password is the whole credential.
    tracing::info!(
        database = %config.redacted(),
        max_connections = MAX_DB_CONNECTIONS,
        statement_timeout = STATEMENT_TIMEOUT,
        "connected to the database"
    );

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

    // Stamped when the signal arrives rather than before `serve`, which is the
    // difference between reporting the drain and reporting the uptime. A
    // `OnceLock` because the shutdown future is the only thing that can know the
    // moment, and it is moved away from here to get it.
    let signalled = Arc::new(OnceLock::new());
    let stamp = Arc::clone(&signalled);

    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            shutdown_signal().await;
            // The `Err` is "already stamped", which one signal cannot produce.
            let _ = stamp.set(Instant::now());
        })
        .await
        .context("server terminated unexpectedly")?;

    // The other half of the line `shutdown_signal` writes, which announces only
    // the intent. Without this, a restart that drained in milliseconds and one
    // that ran to the end of docker's ten-second grace and was killed leave the
    // same trace — and only one of those is a deploy that dropped requests.
    tracing::info!(
        duration_ms = signalled
            .get()
            .map_or(0, |at: &Instant| u64::try_from(at.elapsed().as_millis())
                .unwrap_or(u64::MAX)),
        "drained; exiting"
    );

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
