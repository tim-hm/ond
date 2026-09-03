//! Boot-time configuration. Two values come from the environment: `OND_ENV`
//! and `DATABASE_URL`; everything else derives from the environment name
//! (CLAUDE.md §1.4–1.5), because a variable can drift between a laptop and a
//! deployment while a derived value cannot. The assistant needs no provider
//! key — the EC2 instance profile signs its calls; region and model are constants below.

use std::fmt;
use std::str::FromStr;

use anyhow::{Context, Result};
use sqlx::postgres::PgConnectOptions;

/// Which deployment this process is. Chosen from `OND_ENV`; everything
/// environment-dependent is a `match` on this rather than another variable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Environment {
    Dev,
    Production,
}

/// The resolved boot configuration, held whole on `AppState` for the process's
/// lifetime. Deliberately hard to grow: a field here can differ between a
/// laptop and a deployment without anything noticing, so a new one owes an
/// argument that it cannot be derived from `environment` — most cannot make it.
#[derive(Clone)]
pub struct Config {
    pub environment: Environment,
    pub database_url: String,
    pub port: u16,

    /// Where Prometheus scrapes, and deliberately not `port`:
    /// docs/observability.md wants the scrape target on its own listener so no
    /// edit to whatever fronts the API can expose it by accident. A path on the
    /// main router would not be private — Caddy proxies every path to that
    /// listener; a second listener is private because nothing publishes it.
    pub metrics_port: u16,
}

/// Hand-written because the derive published a credential: `database_url`
/// carries the Postgres password, so one `tracing::error!(?config, …)` would
/// have put it in the production JSON stream with nothing failing to compile.
impl fmt::Debug for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Config")
            .field("environment", &self.environment)
            .field("database_url", &redacted(&self.database_url))
            .field("port", &self.port)
            .field("metrics_port", &self.metrics_port)
            .finish()
    }
}

const REDACTED: &str = "<redacted>";

/// Where the pool points, with the credentials taken out. Parsed rather than
/// cut with string surgery — the parser knows which part is the password, and
/// sqlx's `to_url_lossy` is no shortcut: it writes the password back in. An
/// unparseable value redacts whole, because a `Debug` impl has nowhere to
/// report a failure and guessing is how a password reaches a log.
fn redacted(database_url: &str) -> String {
    PgConnectOptions::from_str(database_url).map_or_else(
        |_| REDACTED.to_owned(),
        |options| {
            format!(
                "{}:{}/{}",
                options.get_host(),
                options.get_port(),
                options.get_database().unwrap_or_default()
            )
        },
    )
}

impl Environment {
    /// Parsing and the "must be one of" error both derive from this array, so
    /// adding a variant is a compile error here *and* a correct parse — a
    /// `match` on `&str` in `load` would accept a new variant silently and
    /// leave the error text quietly lying about what it accepts.
    const ALL: [Self; 2] = [Self::Dev, Self::Production];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Dev => "dev",
            Self::Production => "production",
        }
    }

    fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|env| env.as_str() == value)
    }

    /// Human-readable logs in dev, JSON everywhere else. On the environment
    /// rather than on [`Config`] because the subscriber is installed before the
    /// rest of the configuration is read — a boot error reported before there
    /// is a subscriber reaches a deployment as unparsed text on stderr, the
    /// single failure that must stay legible.
    pub const fn wants_json_logs(self) -> bool {
        matches!(self, Self::Production)
    }
}

impl Config {
    /// Where the pool points, credential taken out — `host:port/name`; the boot
    /// line's `database` field. Until this existed the redaction was reachable
    /// only from a `Debug` impl nothing called, and "connected to the database"
    /// named no database — a first-boot drift on the box once had every nightly
    /// backup dumping the wrong one for eight days.
    pub fn redacted(&self) -> String {
        redacted(&self.database_url)
    }

    /// Whether this process is a developer's machine rather than a deployment.
    /// The two callers gate surfaces a deployment must not carry — cleartext
    /// CORS and gRPC reflection — so a third caller almost certainly belongs
    /// to the same set; check that it does before adding one.
    pub const fn is_local(&self) -> bool {
        matches!(self.environment, Environment::Dev)
    }
}

/// önd owns 29100–29199; this is the first of them. See docs/contributing.md
/// for why the range starts here.
const DEFAULT_PORT: u16 = 29100;

/// The scrape listener. 29101 and 29102 are Postgres and the site preview, so
/// this is the next free number in the block — see the port table in
/// docs/contributing.md, which is the thing to keep in step.
const DEFAULT_METRICS_PORT: u16 = 29103;

/// The app, as Apple names it. Two verifiers check it and must mean the same
/// app: the `bundleId` on an App Store signed transaction and the `aud` of a
/// Sign in with Apple identity token — a genuine Apple token naming another
/// app must fail, so the value is the check. One constant so the verifiers
/// cannot diverge; it has to match `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml`.
pub const BUNDLE_ID: &str = "xyz.holmie.ond";

/// The AWS region the assistant's calls are signed for and sent to. The box is
/// in London, so a coach request reaches Bedrock without leaving the region
/// the deployment lives in; where it goes after that is the inference
/// profile's business. A constant rather than `AWS_REGION`: a drifting region
/// would route coach traffic somewhere `web/privacy.html` does not describe.
pub const BEDROCK_REGION: &str = "eu-west-2";

/// The model, named as an EU cross-region inference profile: Bedrock forwards
/// each call to a destination region, so `web/privacy.html` says "across
/// Amazon's EU regions" and the IAM policy in `infra/main.tf` must grant the
/// foundation model in every destination region (profile-only fails at invoke).
/// A model requiring provider data sharing makes that page untrue — amend it in the same commit.
pub const BEDROCK_MODEL_ID: &str = "eu.anthropic.claude-haiku-4-5-20251001-v1:0";

/// Reads `OND_ENV`. Split from [`load`] because it decides the log format, and
/// the subscriber has to exist before the first thing that can fail —
/// otherwise a deployment's boot failure is text on stderr in the middle of a
/// JSON stream, which ships unparsed. A missing `OND_ENV` is not an error; see
/// [`environment_from`].
pub fn environment() -> Result<Environment> {
    environment_from(std::env::var("OND_ENV"))
}

/// Reads `DATABASE_URL` and derives the rest. A missing value fails the boot
/// rather than defaulting: a server that invented a connection string would
/// start clean and then fail every request. Takes the environment rather than
/// reading it, so the variable deciding how this failure gets *reported* is
/// resolved before this can fail.
pub fn load(environment: Environment) -> Result<Config> {
    let database_url = std::env::var("DATABASE_URL").context(
        "DATABASE_URL is not set — run through `mise run dev`, which supplies it (CLAUDE.md §3)",
    )?;

    Ok(Config {
        environment,
        database_url,
        port: DEFAULT_PORT,
        metrics_port: DEFAULT_METRICS_PORT,
    })
}

/// Interprets the raw `OND_ENV` lookup. Split from `load` so the branching
/// is testable without mutating the process environment.
fn environment_from(var: Result<String, std::env::VarError>) -> Result<Environment> {
    match var {
        Ok(value) => Environment::parse(&value).with_context(|| {
            format!(
                "OND_ENV must be one of {:?}, got `{value}`",
                Environment::ALL.map(Environment::as_str)
            )
        }),
        // Dev is the default because an unset variable means a developer's
        // machine. A deployment that forgets to set it gets dev's permissive
        // CORS, pretty logs, and gRPC reflection — so this fallback does sit in
        // front of things a deployment should not expose, and the Caddyfile
        // declines to proxy the reflection path rather than trusting it alone.
        Err(std::env::VarError::NotPresent) => Ok(Environment::Dev),
        Err(e) => Err(e).context("OND_ENV is not valid UTF-8"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_every_environment_name() {
        for environment in Environment::ALL {
            let parsed = environment_from(Ok(environment.as_str().to_owned()));
            assert_eq!(parsed.expect("a known name parses"), environment);
        }
    }

    #[test]
    fn defaults_to_dev_when_unset() {
        let parsed = environment_from(Err(std::env::VarError::NotPresent));
        assert_eq!(parsed.expect("absence is not an error"), Environment::Dev);
    }

    /// The check that survives the next editor: whatever else the impl prints,
    /// the Postgres password may not appear. Re-deriving `Debug` fails this.
    #[test]
    fn debug_redacts_the_database_password() {
        let config = Config {
            environment: Environment::Production,
            database_url: "postgres://postgres:hunter2@db:5432/ond?sslmode=disable".to_owned(),
            port: DEFAULT_PORT,
            metrics_port: DEFAULT_METRICS_PORT,
        };

        let rendered = format!("{config:?}");
        assert!(!rendered.contains("hunter2"), "{rendered}");
        assert!(
            rendered.contains("db:5432/ond"),
            "the host and database name are the part worth keeping: {rendered}"
        );
    }

    /// The error text derives from `Environment::ALL`, so it names every
    /// accepted value — this pins that it can't quietly go stale.
    #[test]
    fn an_unknown_name_lists_the_accepted_values() {
        let error = environment_from(Ok("staging".to_owned())).expect_err("staging is not a name");
        let message = format!("{error:#}");
        for environment in Environment::ALL {
            assert!(message.contains(environment.as_str()));
        }
        assert!(message.contains("staging"));
    }
}
