//! Disposable Postgres databases and their production routers.

use std::collections::HashSet;
use std::str::FromStr;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, SystemTime};

use api::account::IdentityTokenVerifier;
use api::assistant::{DisabledModelClient, ModelClient};
use api::config::{Config, Environment};
use api::entitlement::{AppStoreVerifier, TransactionVerifier};
use api::state::AppState;
use api::throttle::Throttle;
use axum::Router;
use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};

use super::{
    ScriptedIdentityVerifier, build_app, build_app_with, build_app_with_throttle, subscribe,
};

const TEST_DATABASE_PREFIX: &str = "ond_test_";

/// Postgres truncates identifiers past this and would silently collide two
/// tests whose names share a long prefix.
const MAX_IDENTIFIER_BYTES: usize = 63;

/// How long a test database outlives its run before the sweep takes it: long
/// enough that a failing test's database survives for post-mortem inspection
/// and past any *concurrent* run still in flight; short enough that a machine
/// running the gate all day does not accumulate them.
const ABANDONED_AFTER: Duration = Duration::from_hours(1);

/// A freshly migrated and seeded database, owned by one test.
pub struct TestDatabase {
    pub pool: PgPool,

    /// Who [`Self::given_subscriber`] has already put on the paid tier. The
    /// quota suites call the subscribing helpers fifty times over, so without
    /// this the assistant suite spends fifty round trips writing one row. A
    /// set rather than a flag because a test can have two callers, one of
    /// which may deliberately not be subscribed.
    subscribed: Mutex<HashSet<String>>,
}

/// This process's suffix on every database name it mints: the mint second then
/// the process id, each as eight hex digits — the seconds half is how
/// [`sweep_abandoned`] reads a database's age off its name. The suffix is the
/// isolation: a deterministic name once let two concurrent gate runs drop each
/// other's databases mid-test. A failing test's database is still findable as `ond_test_<test_name>_*`.
static RUN_STAMP: LazyLock<String> = LazyLock::new(|| {
    let seconds = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("the clock sits after 1970")
        .as_secs();
    format!("{seconds:08x}{:08x}", std::process::id())
});

/// When a stamped name was minted, or `None` for a suffix this harness never
/// wrote — which the sweep reads as abandoned.
fn minted_at(stamp: &str) -> Option<SystemTime> {
    if stamp.len() != 16 || u64::from_str_radix(stamp, 16).is_err() {
        return None;
    }

    let seconds = u64::from_str_radix(&stamp[..8], 16).ok()?;
    Some(SystemTime::UNIX_EPOCH + Duration::from_secs(seconds))
}

/// Drops test databases left behind by runs more than [`ABANDONED_AFTER`]
/// ago, once per test process. Age is read off each name's stamp; a suffix
/// that is not one is a database this harness did not mint and is dropped as
/// abandoned too. Databases from a live concurrent run carry a recent stamp
/// and are left alone.
async fn sweep_abandoned(maintenance: &PgPool) {
    static SWEPT: tokio::sync::OnceCell<()> = tokio::sync::OnceCell::const_new();

    SWEPT
        .get_or_init(|| async {
            let names: Vec<String> =
                sqlx::query_scalar("SELECT datname FROM pg_database WHERE datname LIKE $1")
                    .bind(format!("{TEST_DATABASE_PREFIX}%"))
                    .fetch_all(maintenance)
                    .await
                    .expect("the database catalogue is readable");

            for name in names {
                let abandoned = name
                    .rsplit_once('_')
                    .and_then(|(_, stamp)| minted_at(stamp))
                    .is_none_or(|minted| minted + ABANDONED_AFTER < SystemTime::now());

                if abandoned {
                    // Errors ignored: two processes sweeping at once race on
                    // the same names, and housekeeping losing that race must
                    // not read as a test failure — the winner made it moot.
                    drop(
                        sqlx::query(sqlx::AssertSqlSafe(format!(
                            "DROP DATABASE IF EXISTS {} WITH (FORCE)",
                            migrate::quote_identifier(&name)
                        )))
                        .execute(maintenance)
                        .await,
                    );
                }
            }
        })
        .await;
}

impl TestDatabase {
    /// Creates `ond_test_<test_name>_<run stamp>`, migrated and seeded.
    ///
    /// Unique per run — see [`RUN_STAMP`] for why — so a test that fails
    /// leaves its database behind for post-mortem inspection without the next
    /// run touching it; [`sweep_abandoned`] reclaims it an hour later.
    pub async fn create(test_name: &str) -> Self {
        let name = format!("{TEST_DATABASE_PREFIX}{test_name}_{}", *RUN_STAMP);
        assert!(
            name.len() <= MAX_IDENTIFIER_BYTES,
            "test name `{test_name}` makes an over-long database identifier"
        );

        let options = PgConnectOptions::from_str(&database_url())
            .expect("DATABASE_URL is a valid Postgres connection string");

        let maintenance = migrate::connect_maintenance(&options)
            .await
            .expect("Postgres is reachable — is `mise run dev:db` running?");

        sweep_abandoned(&maintenance).await;

        // `FORCE` terminates connections a previously killed test process left
        // open; without it a crashed run wedges its own database until restart.
        // With run-unique names this is a no-op except when one process runs
        // the same test twice.
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DROP DATABASE IF EXISTS {} WITH (FORCE)",
            migrate::quote_identifier(&name)
        )))
        .execute(&maintenance)
        .await
        .expect("the previous test database drops");

        migrate::create_database_if_absent(&options, &name)
            .await
            .expect("the test database is created");

        let pool = PgPoolOptions::new()
            .max_connections(2)
            .connect_with(options.database(&name))
            .await
            .unwrap_or_else(|e| panic!("failed to connect to `{name}`: {e}"));

        migrate::apply(&pool)
            .await
            .expect("the schema and seed apply to a fresh database");

        Self {
            pool,
            subscribed: Mutex::new(HashSet::new()),
        }
    }

    /// The router the binary serves, over this database. No language model
    /// behind the seam: a test that is not about the assistant must behave the
    /// same whether or not a key is in the environment. `DisabledModelClient`
    /// is not a stub for the occasion — it is what a deployment without a key runs.
    pub fn app(&self) -> Router {
        build_app(self.pool.clone())
    }

    /// The same router with a scripted model behind the seam. Paired with
    /// [`Self::app`] rather than folded into one argument: the model is the
    /// one thing that varies, and twenty unrelated tests should not carry it.
    pub fn app_with_model(&self, assistant: Arc<dyn ModelClient>) -> Router {
        build_app_with(
            self.pool.clone(),
            assistant,
            Arc::new(AppStoreVerifier),
            ScriptedIdentityVerifier::refusing(),
        )
    }

    /// Puts somebody on the paid tier, once per database however often it is
    /// asked. The memo makes it safe for a fixture to call on every helper, so
    /// no test has to remember the setup and none can forget it. Idempotent
    /// either way; the memo saves the round trip, not correctness.
    pub async fn given_subscriber(&self, user: &str) {
        if !self
            .subscribed
            .lock()
            .expect("the memo is never held across a panic")
            .insert(user.to_owned())
        {
            return;
        }

        subscribe(&self.pool, user, "PLUS").await;
    }

    /// The same router with a scripted App Store verifier behind the seam.
    /// Needed for the same reason the model seam is: no test can hold an
    /// Apple-signed transaction, so a suite driven through the real verifier
    /// could only ever assert that everything is rejected.
    pub fn app_with_verifier(&self, entitlement: Arc<dyn TransactionVerifier>) -> Router {
        build_app_with(
            self.pool.clone(),
            Arc::new(DisabledModelClient),
            entitlement,
            ScriptedIdentityVerifier::refusing(),
        )
    }

    /// The same router with a scripted Sign in with Apple verifier behind the
    /// seam — load-bearing twice over: no test can hold a token Apple signed,
    /// *and* the real verifier would ask Apple for the key to check it with.
    pub fn app_with_identity(&self, account: Arc<dyn IdentityTokenVerifier>) -> Router {
        build_app_with(
            self.pool.clone(),
            Arc::new(DisabledModelClient),
            Arc::new(AppStoreVerifier),
            account,
        )
    }

    /// The scrape listener's router, which is a different router on a different
    /// port in the binary — so a test that drove [`Self::app`] would prove
    /// nothing about it.
    pub fn metrics_app(&self) -> Router {
        api::metrics_router(AppState::with_throttle(
            self.pool.clone(),
            Config {
                environment: Environment::Dev,
                database_url: String::new(),
                port: 0,
                metrics_port: 0,
            },
            Arc::new(DisabledModelClient),
            Arc::new(AppStoreVerifier),
            ScriptedIdentityVerifier::refusing(),
            Throttle::default(),
        ))
    }

    /// The same router with the rate limiter's clock stopped — for
    /// `throttle.rs`, the only suite that spends a whole budget. A burst of
    /// several hundred real requests crosses a window boundary about one run
    /// in seven and is served twice its allowance; stopping the clock puts the
    /// burst in one window by construction, so the assertion can be an equality.
    pub fn app_with_stopped_throttle(&self) -> Router {
        build_app_with_throttle(
            self.pool.clone(),
            Arc::new(DisabledModelClient),
            Arc::new(AppStoreVerifier),
            ScriptedIdentityVerifier::refusing(),
            Throttle::with_clock(stopped_clock),
        )
    }
}

/// A clock that never leaves the first window, so no burst can outlast one.
fn stopped_clock() -> Duration {
    Duration::ZERO
}

fn database_url() -> String {
    std::env::var("DATABASE_URL").expect(
        "DATABASE_URL is not set — run these through `mise run test:e2e`, which supplies it",
    )
}
