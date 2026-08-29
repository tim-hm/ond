//! The seeded phase ranges, held for the life of the process.
//!
//! A named sibling of `repository.rs`: `crate::state` and another feature's
//! handler both name it, and `docs/code-structure.md` bars importing a
//! feature's repository from outside it. Only the memoisation is here.

use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::OnceCell;

use super::errors::UserTechniqueError;
use super::repository;
use super::types::PhaseLimits;

/// [`repository::phase_limits`], derived once per process.
///
/// The catalogue changes only on a deploy, which restarts this process. One
/// cache per transport instance, so each e2e stack derives from its own
/// database. `Arc` because the assistant's reply stream outlives its RPC.
pub struct PhaseLimitsCache(OnceCell<Arc<PhaseLimits>>);

impl PhaseLimitsCache {
    pub const fn new() -> Self {
        Self(OnceCell::const_new())
    }

    /// The cached limits, deriving them on the first call.
    ///
    /// An empty derivation errors rather than caching. It happens when a
    /// request lands between `dev:db:reset`'s schema and seed steps. Erroring
    /// leaves the cell empty, so the next request re-derives.
    pub async fn get(&self, pool: &PgPool) -> Result<&Arc<PhaseLimits>, UserTechniqueError> {
        self.0
            .get_or_try_init(|| async {
                let limits = repository::phase_limits(pool).await?;
                if limits.iter().next().is_none() {
                    return Err(UserTechniqueError::Inconsistent(
                        "the catalogue has no phase limits to derive".to_owned(),
                    ));
                }
                Ok(Arc::new(limits))
            })
            .await
    }
}
