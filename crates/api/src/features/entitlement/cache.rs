//! The product census, reused for one scrape interval.

use std::future::Future;
use std::time::{Duration, Instant};

use sqlx::PgPool;
use tokio::sync::Mutex;

use super::errors::EntitlementError;
use super::service;
use super::types::Census;

/// Prometheus scrapes every fifteen seconds in production. A minute keeps four
/// scrapes on one population scan while still making the dashboard react on a
/// human timescale.
const CENSUS_TTL: Duration = Duration::from_mins(1);

#[derive(Clone, Copy)]
struct Cached {
    census: Option<Census>,
    expires_at: Instant,
}

/// The census visible to one scrape.
///
/// `refresh_error` is present only for the request that performed a failed
/// refresh. The handler logs it once; later scrapes reuse the unknown reading
/// without turning one database outage into a warning every fifteen seconds.
pub struct CensusSnapshot {
    /// The verified population, or `None` while the database is unavailable.
    pub census: Option<Census>,

    /// The failure from this scrape's refresh, for the handler to log once.
    pub refresh_error: Option<EntitlementError>,
}

/// A single-flight, one-minute cache for the population scan.
///
/// The state lock serialises misses as well as protecting the cached value. A
/// waiter checks the value after the refresher releases it, so concurrent
/// scrapes share one query rather than queueing one query each. Failure is
/// cached as an unknown census, not as the previous value: the dashboard must
/// never keep presenting a population the database can no longer verify.
pub struct CensusCache {
    cached: Mutex<Option<Cached>>,
}

impl CensusCache {
    /// Creates an empty cache, ready to derive its first census on demand.
    pub const fn new() -> Self {
        Self {
            cached: Mutex::const_new(None),
        }
    }

    /// Returns the current census, refreshing it when its minute has elapsed.
    pub async fn get(&self, pool: &PgPool) -> CensusSnapshot {
        self.get_at(Instant::now(), || service::census(pool)).await
    }

    async fn get_at<F, Fut>(&self, now: Instant, load: F) -> CensusSnapshot
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<Census, EntitlementError>>,
    {
        let mut cached = self.cached.lock().await;
        if let Some(current) = *cached
            && current.expires_at > now
        {
            return CensusSnapshot {
                census: current.census,
                refresh_error: None,
            };
        }

        let (census, refresh_error) = match load().await {
            Ok(census) => (Some(census), None),
            Err(error) => (None, Some(error)),
        };
        *cached = Some(Cached {
            census,
            expires_at: now + CENSUS_TTL,
        });
        drop(cached);

        CensusSnapshot {
            census,
            refresh_error,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    fn census(users: i64) -> Census {
        Census {
            users,
            plus: users,
            gross_mrr_usd: 0.0,
        }
    }

    #[tokio::test]
    async fn a_fresh_reading_is_reused() {
        let cache = CensusCache::new();
        let loads = AtomicUsize::new(0);
        let now = Instant::now();

        let first = cache
            .get_at(now, || async {
                loads.fetch_add(1, Ordering::SeqCst);
                Ok(census(1))
            })
            .await;
        let second = cache
            .get_at(now + Duration::from_secs(59), || async {
                loads.fetch_add(1, Ordering::SeqCst);
                Ok(census(2))
            })
            .await;

        assert_eq!(first.census, Some(census(1)));
        assert_eq!(second.census, Some(census(1)));
        assert_eq!(loads.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn an_expired_reading_is_refreshed() {
        let cache = CensusCache::new();
        let now = Instant::now();

        cache.get_at(now, || async { Ok(census(1)) }).await;
        let refreshed = cache
            .get_at(now + CENSUS_TTL, || async { Ok(census(2)) })
            .await;

        assert_eq!(refreshed.census, Some(census(2)));
    }

    #[tokio::test]
    async fn a_failed_refresh_replaces_stale_data_with_unknown() {
        let cache = CensusCache::new();
        let loads = AtomicUsize::new(0);
        let now = Instant::now();

        cache
            .get_at(now, || async {
                loads.fetch_add(1, Ordering::SeqCst);
                Ok(census(1))
            })
            .await;
        let failed = cache
            .get_at(now + CENSUS_TTL, || async {
                loads.fetch_add(1, Ordering::SeqCst);
                Err(EntitlementError::Missing)
            })
            .await;
        let reused = cache
            .get_at(now + CENSUS_TTL + Duration::from_secs(1), || async {
                loads.fetch_add(1, Ordering::SeqCst);
                Ok(census(3))
            })
            .await;

        assert!(failed.census.is_none());
        assert!(failed.refresh_error.is_some());
        assert!(reused.census.is_none());
        assert!(reused.refresh_error.is_none());
        assert_eq!(loads.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn concurrent_misses_share_one_refresh() {
        let cache = Arc::new(CensusCache::new());
        let loads = Arc::new(AtomicUsize::new(0));
        let now = Instant::now();

        let first = {
            let cache = Arc::clone(&cache);
            let loads = Arc::clone(&loads);
            tokio::spawn(async move {
                cache
                    .get_at(now, || async move {
                        loads.fetch_add(1, Ordering::SeqCst);
                        tokio::task::yield_now().await;
                        Ok(census(1))
                    })
                    .await
                    .census
            })
        };
        let second = {
            let cache = Arc::clone(&cache);
            let loads = Arc::clone(&loads);
            tokio::spawn(async move {
                cache
                    .get_at(now, || async move {
                        loads.fetch_add(1, Ordering::SeqCst);
                        Ok(census(2))
                    })
                    .await
                    .census
            })
        };

        let (first, second) = tokio::join!(first, second);
        assert_eq!(first.unwrap(), second.unwrap());
        assert_eq!(loads.load(Ordering::SeqCst), 1);
    }
}
