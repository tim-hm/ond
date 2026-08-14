//! Production application assembly over injectable test seams.

use std::sync::Arc;

use api::account::IdentityTokenVerifier;
use api::assistant::{DisabledModelClient, ModelClient};
use api::config::{Config, Environment};
use api::entitlement::{AppStoreVerifier, TransactionVerifier};
use api::state::AppState;
use api::throttle::Throttle;
use axum::Router;
use sqlx::PgPool;

use super::ScriptedIdentityVerifier;

/// Assembles the production router over an arbitrary pool.
pub fn build_app(pool: PgPool) -> Router {
    build_app_with(
        pool,
        Arc::new(DisabledModelClient),
        Arc::new(AppStoreVerifier),
        ScriptedIdentityVerifier::refusing(),
    )
}

/// [`build_app`], plus all three of the seams a deployment chooses at startup.
pub fn build_app_with(
    pool: PgPool,
    assistant: Arc<dyn ModelClient>,
    entitlement: Arc<dyn TransactionVerifier>,
    account: Arc<dyn IdentityTokenVerifier>,
) -> Router {
    build_app_with_throttle(pool, assistant, entitlement, account, Throttle::new())
}

/// [`build_app_with`], plus the rate limiter — which every suite but one wants
/// built exactly as a deployment builds it.
pub(super) fn build_app_with_throttle(
    pool: PgPool,
    assistant: Arc<dyn ModelClient>,
    entitlement: Arc<dyn TransactionVerifier>,
    account: Arc<dyn IdentityTokenVerifier>,
    throttle: Throttle,
) -> Router {
    let config = Config {
        environment: Environment::Dev,
        // Read only while building the pool, which the caller has already done.
        // Nothing downstream of `AppState` looks at it.
        database_url: String::new(),
        // Neither port is bound here: the harness drives the router through
        // `tower::ServiceExt::oneshot` rather than over a socket, so these exist
        // to satisfy the struct and nothing reads them.
        port: 0,
        metrics_port: 0,
    };

    api::build_app(AppState::with_throttle(
        pool,
        config,
        assistant,
        entitlement,
        account,
        throttle,
    ))
    .expect("the router assembles")
}
