//! The curated catalogue, held for the life of the process.
//!
//! A named sibling for `user_technique::cache`'s reason: this is the piece the
//! composition root holds and a second feature reads through, so it is
//! published deliberately rather than reached for behind the service.

use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::OnceCell;

use super::errors::TechniqueError;
use super::service;
use super::types::{Reference, Technique};

/// Everything curated that an assistant request reads.
///
/// One seed transaction writes the catalogue and the routes, so one
/// non-emptiness check vouches for both — see [`CuratedCache::get`]. The chat
/// reply stream outlives its RPC, so each half keeps its own `Arc`.
pub struct Curated {
    pub catalogue: Arc<Vec<Technique>>,
    pub reference: Arc<Reference>,
}

/// [`Curated`], derived once per process and then read from memory.
///
/// Only a migration reseeds this data, and a migration restarts the process — `PhaseLimitsCache`'s
/// invariant, over the same tables. It replaces six queries per chat and per recommendation. One
/// cache per transport instance, not a process global, so each e2e stack derives from its own database.
pub struct CuratedCache(OnceCell<Curated>);

impl CuratedCache {
    pub const fn new() -> Self {
        Self(OnceCell::const_new())
    }

    /// The cached data, deriving it on the first call.
    ///
    /// Derived on demand, not at boot: a failure leaves the cell empty to retry, where a boot
    /// read could not start on an unseeded database. An empty catalogue means `migrate::seed`
    /// has not committed: refused rather than cached, and that check covers the routes too.
    pub async fn get(&self, pool: &PgPool) -> Result<&Curated, TechniqueError> {
        self.0
            .get_or_try_init(|| async {
                let catalogue = service::catalogue(pool).await?;
                if catalogue.is_empty() {
                    return Err(TechniqueError::Inconsistent(
                        "the catalogue holds no techniques to derive from".to_owned(),
                    ));
                }

                let reference = service::reference(pool).await?;
                Ok(Curated {
                    catalogue: Arc::new(catalogue),
                    reference: Arc::new(reference),
                })
            })
            .await
    }
}
