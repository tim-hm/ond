//! The one object injected into handlers.

use std::sync::Arc;

use sqlx::PgPool;

use crate::config::Config;
use crate::features::account::verifier::IdentityTokenVerifier;
use crate::features::assistant::model::ModelClient;
use crate::features::entitlement::cache::CensusCache;
use crate::features::entitlement::verifier::TransactionVerifier;
use crate::features::technique::cache::CuratedCache;
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

    /// The language model, chosen once at startup. Injected exactly as the
    /// pool is: it is the other thing in this process that talks to something
    /// outside it, and a handler holding a concrete client would be a handler
    /// no test could point somewhere harmless.
    pub assistant: Arc<dyn ModelClient>,

    /// The App Store signature checker. Injected for the same reason as the
    /// model, with the opposite emphasis: this seam lets a test supply a
    /// transaction Apple never signed. Nothing configures it — the trust
    /// anchor is compiled in — so the field exists purely as the seam.
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

    /// The widest interval the seeded catalogue puts each kind of phase in,
    /// derived once per process. Two readers: the `user_technique` handler and
    /// the assistant, whose save-this-pattern card is validated against these
    /// limits so the server can never propose an exercise the create RPC would
    /// refuse — hence one cache on the object both handlers hold.
    pub phase_limits: PhaseLimitsCache,

    /// The seeded techniques and the curated routes into them, derived once
    /// per process. Here on [`AppState::phase_limits`]' terms: the same
    /// tables, the same "only a migration changes this, and a migration
    /// restarts the process" invariant, and the assistant as a second reader.
    pub curated: CuratedCache,

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
        assistant: Arc<dyn ModelClient>,
        entitlement: Arc<dyn TransactionVerifier>,
        account: Arc<dyn IdentityTokenVerifier>,
    ) -> Arc<Self> {
        Self::with_throttle(
            pool,
            config,
            assistant,
            entitlement,
            account,
            Throttle::new(),
        )
    }

    /// The same state with the rate limiter supplied rather than built. The
    /// one caller is `tests/e2e/throttle.rs`, which stops the limiter's clock
    /// so a burst cannot straddle a window boundary — [`Throttle::with_clock`]
    /// has the reasoning. A separate constructor so the composition roots that
    /// do not care about the throttle do not have to name it.
    pub fn with_throttle(
        pool: PgPool,
        config: Config,
        assistant: Arc<dyn ModelClient>,
        entitlement: Arc<dyn TransactionVerifier>,
        account: Arc<dyn IdentityTokenVerifier>,
        throttle: Throttle,
    ) -> Arc<Self> {
        Arc::new(Self {
            pool,
            config,
            assistant,
            entitlement,
            account,
            throttle,
            phase_limits: PhaseLimitsCache::new(),
            curated: CuratedCache::new(),
            census: CensusCache::new(),
        })
    }
}
