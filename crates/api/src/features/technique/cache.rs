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

/// Everything curated that an assistant request reads: every technique with the
/// stages it plays, and the routes into them.
///
/// One value rather than two cached separately because they are written by one
/// seed transaction, which is what lets a single non-emptiness check vouch for
/// both — see [`CuratedCache::get`].
///
/// Each half is behind its own `Arc` rather than the pair being behind one: a
/// reader wants the catalogue or the routes, never the box, and the chat's
/// reply stream needs the catalogue by value because it outlives the RPC that
/// built it and resolves slugs inside itself. Two refcounts per request is what
/// that costs instead of a copy of either.
pub struct Curated {
    pub catalogue: Arc<Vec<Technique>>,
    pub reference: Arc<Reference>,
}

/// [`Curated`], derived once per process and then read from memory.
///
/// The same invariant `user_technique`'s `PhaseLimitsCache` rests on, over the
/// same tables: this is curated reference data, reseeded only by a migration,
/// and a migration restarts this process. Before the cache, the six queries
/// behind it ran on every chat and recommendation — for data that
/// provably could not have changed since the last one.
///
/// One cache per transport instance rather than a process global, so each e2e
/// stack derives from its own database.
pub struct CuratedCache(OnceCell<Curated>);

impl CuratedCache {
    pub const fn new() -> Self {
        Self(OnceCell::const_new())
    }

    /// The cached data, deriving it on the first call.
    ///
    /// Sequential reads, unlike the fan-out this replaced: a concurrent
    /// derivation was worth its pool connections while it ran per request, and
    /// this one runs per process.
    ///
    /// Derived on demand rather than at boot, which is the same choice
    /// `PhaseLimitsCache` makes and for its reason: a failure here leaves the
    /// cell empty for the next caller to retry, where a boot that read the
    /// catalogue would turn a database not yet seeded into a process that will
    /// not start.
    ///
    /// An empty catalogue is refused rather than cached, for the reason
    /// `PhaseLimitsCache` refuses an empty derivation: the one way it happens
    /// is a request landing before `migrate::seed`'s transaction commits, and
    /// caching that answer would leave the coach with nothing to recommend
    /// until the process restarts. That one check stands for the routes as
    /// well — techniques, foundations, occasions and the progression are
    /// written in that single transaction, so a catalogue this reader can see
    /// means the rest of it committed with it.
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
