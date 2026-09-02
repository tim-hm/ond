//! Brings a `ond` database into existence and up to date.
//!
//! `main.rs` is one caller. The API's `tests/e2e` harness is the other, so a
//! test database and a deployed one are built by the same code.

pub mod seed;

use anyhow::{Context, Result};
use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};

/// Applies `migrations/`, then reconciles the technique catalogue.
///
/// Idempotent, which is what lets `mise run migrate` be the one command a new
/// clone needs and lets the test harness call it on a database it just created.
pub async fn apply(pool: &PgPool) -> Result<()> {
    sqlx::migrate!("./migrations")
        .run(pool)
        .await
        .context("failed to apply migrations")?;
    tracing::info!("migrations applied");

    seed::run(pool).await
}

/// Creates the database if it does not already exist.
///
/// `CREATE DATABASE` cannot run from inside the database being created, so this
/// goes through the maintenance connection.
pub async fn create_database_if_absent(options: &PgConnectOptions, name: &str) -> Result<()> {
    let pool = connect_maintenance(options).await?;

    let exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = $1)")
            .bind(name)
            .fetch_one(&pool)
            .await
            .context("failed to check whether the database exists")?;

    if exists {
        return Ok(());
    }

    // `AssertSqlSafe` is sqlx 0.9's opt-out from the `&'static str` requirement on
    // query text. The audit it asks for is `quote_identifier`.
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "CREATE DATABASE {}",
        quote_identifier(name)
    )))
    .execute(&pool)
    .await
    .with_context(|| format!("failed to create database `{name}`"))?;

    tracing::info!(database = %name, "database created");
    Ok(())
}

/// Opens a one-connection pool on `postgres` — the database guaranteed to exist
/// on a stock server, and therefore the only place statements that cannot run
/// inside the target database can run.
///
/// The target's credentials and TLS settings carry across unchanged.
pub async fn connect_maintenance(options: &PgConnectOptions) -> Result<PgPool> {
    PgPoolOptions::new()
        .max_connections(1)
        .connect_with(maintenance_options(options))
        .await
        .context("failed to connect to the `postgres` maintenance database")
}

/// Derives the maintenance connection's options from the target's.
///
/// `.database()` swaps only the database name; credentials, TLS settings, and
/// every other query-string parameter carry across structurally.
fn maintenance_options(options: &PgConnectOptions) -> PgConnectOptions {
    options.clone().database("postgres")
}

/// Quotes a Postgres identifier for interpolation into a statement.
///
/// `CREATE DATABASE` and `DROP DATABASE` take an identifier, and an identifier
/// cannot be a bind parameter. It is public so that every caller that builds
/// such a statement escapes the name the same way.
#[must_use]
pub fn quote_identifier(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use sqlx::postgres::PgSslMode;

    use super::*;

    /// Dropping the query string here would silently change the maintenance
    /// connection's TLS mode — the exact failure string surgery invites.
    #[test]
    fn carries_the_query_string_onto_the_maintenance_url() {
        let options = PgConnectOptions::from_str(
            "postgres://postgres:postgres@localhost:29101/ond?sslmode=require",
        )
        .expect("a valid connection string");

        let maintenance = maintenance_options(&options);

        assert_eq!(maintenance.get_database(), Some("postgres"));
        assert!(matches!(maintenance.get_ssl_mode(), PgSslMode::Require));
    }

    #[test]
    fn quotes_a_plain_identifier() {
        assert_eq!(quote_identifier("ond"), "\"ond\"");
    }

    /// Doubling is what stops an embedded `"` from closing the identifier early
    /// and letting the remainder of the name parse as SQL.
    #[test]
    fn doubles_embedded_quotes() {
        assert_eq!(quote_identifier(r#"a"b"#), r#""a""b""#);
    }
}
