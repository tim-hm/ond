//! The seeded phase ranges, held for the life of the process.
//!
//! A named sibling rather than a struct in `repository.rs`, because this is the
//! piece the composition root holds: `crate::state` names it and a second
//! feature's handler reads it, and a `use crate::features::…::repository::…`
//! from outside the feature is the backdoor import `docs/code-structure.md`
//! rules out. The `JOIN`/`GROUP BY` that fills the cache stays where all SQL
//! lives; only the memoisation is here.

use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::OnceCell;

use super::errors::UserTechniqueError;
use super::repository;
use super::types::PhaseLimits;

/// [`repository::phase_limits`], derived once per process and then read from
/// memory.
///
/// The ranges derive purely from the seeded catalogue, and the catalogue
/// changes only when a deploy re-runs the migrations — which restarts this
/// process and so re-derives. Caching here keeps the "derived, not seeded
/// twice" property while taking the `JOIN`/`GROUP BY` off every list, create
/// and update. One cache per transport instance rather than a process global,
/// so each e2e stack derives from its own database.
///
/// Behind an `Arc` because one caller — the assistant, whose reply stream
/// outlives the RPC that built it — needs the limits by value. A refcount is
/// what it takes there instead of a copy of the derivation on every chat turn.
pub struct PhaseLimitsCache(OnceCell<Arc<PhaseLimits>>);

impl PhaseLimitsCache {
    pub const fn new() -> Self {
        Self(OnceCell::const_new())
    }

    /// The cached limits, deriving them on the first call.
    ///
    /// An empty derivation is refused rather than cached. The one way it
    /// happens is a request landing between `dev:db:reset`'s schema and seed
    /// steps, and caching that answer would refuse every create until the
    /// process restarts; erroring instead leaves the cell empty, so the next
    /// request re-derives and the cache stays self-healing.
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
