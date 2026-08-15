//! The public liveness endpoint.

use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
pub(super) struct Health {
    status: &'static str,
}

/// Reports process liveness without touching the database.
///
/// A health check that fails when Postgres is unreachable turns a recoverable
/// dependency outage into a restart loop of a process that was fine.
pub(super) async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}
