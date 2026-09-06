//! The one object injected into handlers.

use std::sync::Arc;

use sqlx::PgPool;

use crate::config::Config;
use crate::features::account::verifier::IdentityTokenVerifier;
use crate::features::entitlement::cache::CensusCache;
use crate::features::entitlement::verifier::TransactionVerifier;
use crate::features::user_technique::cache::PhaseLimitsCache;
use crate::throttle::Throttle;

/// Shared as `Arc<AppState>` by both transports.
///
/// Flat on purpose. Each field is either process configuration, a boundary
/// dependency, or shared process state; grouping by incidental type would only
/// add indirection between a handler and the dependency it names.
pub struct AppState {
    pub pool: PgPool,
    pub config: Config,

    /// Tests inject a verifier to supply transactions Apple never signed.
    /// The production verifier uses a compiled-in Apple trust anchor.
    pub entitlement: Arc<dyn TransactionVerifier>,

    /// The Sign in with Apple credential checker. Here for the same reason as
    /// the App Store verifier, plus one thing behind it: this one holds
    /// Apple's published keys, so the seam also keeps a test suite off the
    /// network rather than merely off Apple's signatures.
    pub account: Arc<dyn IdentityTokenVerifier>,

    /// What one caller may spend, on requests and on new identities. The one
    /// field here that is *not* a seam: it is on `AppState` because its two
    /// readers — the layer in `build_app` and `identity::resolve` — must share
    /// one set of counters. Only its clock is a caller's business; see
    /// [`AppState::with_throttle`].
    pub throttle: Throttle,

    pub phase_limits: PhaseLimitsCache,

    /// The population scan behind the private metrics endpoint. Feature-owned
    /// because active-subscription meaning and gross monthly value are
    /// entitlement rules; on the shared state so every scrape shares one
    /// single-flight, minute-long reading.
    pub census: CensusCache,
}

impl AppState {
    /// The state a deployment runs, rationing against the wall clock.
    pub fn new(
        pool: PgPool,
        config: Config,
        entitlement: Arc<dyn TransactionVerifier>,
        account: Arc<dyn IdentityTokenVerifier>,
    ) -> Arc<Self> {
        Self::with_throttle(pool, config, entitlement, account, Throttle::new())
    }

    /// The same state with the rate limiter supplied rather than built. The
    /// one caller is `tests/e2e/throttle.rs`, which stops the limiter's clock
    /// so a burst cannot straddle a window boundary — [`Throttle::with_clock`]
    /// has the reasoning. A separate constructor so the composition roots that
    /// do not care about the throttle do not have to name it.
    pub fn with_throttle(
        pool: PgPool,
        config: Config,
        entitlement: Arc<dyn TransactionVerifier>,
        account: Arc<dyn IdentityTokenVerifier>,
        throttle: Throttle,
    ) -> Arc<Self> {
        Arc::new(Self {
            pool,
            config,
            entitlement,
            account,
            throttle,
            phase_limits: PhaseLimitsCache::new(),
            census: CensusCache::new(),
        })
    }
}
