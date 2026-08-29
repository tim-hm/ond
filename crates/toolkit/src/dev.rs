//! What a purchase and a Sign in with Apple would have written, reachable
//! from a terminal. `sign_in` exists because the real route is an identity
//! token verified against Apple's live JWKS, and that check deliberately has
//! no `OND_ENV` bypass — a verifier that can be stubbed ships stubbed.

#![allow(
    clippy::print_stdout,
    reason = "the granted row and the credential are the output"
)]

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use ring::digest::{SHA256, digest};
use ring::rand::{SecureRandom, SystemRandom};
use sqlx::PgPool;
use uuid::Uuid;

use anyhow::{Context, Result, bail};

/// Grant önd+ for a year to `user`, or to the most recently created user.
///
/// Writes what a real App Store purchase would have; a simulator purchase
/// cannot (docs/contributing.md). Defaulting to the newest user is harmless
/// here, unlike in [`sign_in`].
pub async fn plus(user: Option<&str>) -> Result<()> {
    let pool = pool().await?;
    let id = if let Some(id) = user {
        parse_user(id)?
    } else {
        let id: Option<Uuid> =
            sqlx::query_scalar("select id from users order by created_at desc limit 1")
                .fetch_optional(&pool)
                .await?;
        let id = id.context("no users yet — open the app once so it creates one")?;
        println!("no user id given, using the newest: {id}");
        id
    };

    // `returning` rather than trusting the exit status: UPDATE 0 is a
    // success, so a typo'd id would otherwise look exactly like a granted one
    // — and this task exists for the case where the coach already appears
    // broken.
    let granted: Option<Uuid> = sqlx::query_scalar(
        "update users set subscription_tier = 'PLUS', \
         subscription_until = now() + interval '1 year' where id = $1 returning id",
    )
    .bind(id)
    .fetch_optional(&pool)
    .await?;
    match granted {
        Some(id) => {
            println!("granted önd+ to {id} for a year");
            Ok(())
        }
        None => bail!("no user with id {id}"),
    }
}

/// Sign `user` in without the Apple sheet, or create a fresh identity.
/// Binds an Apple id derived from the user id, and mints a session credential
/// in the same breath because `identity::resolve` refuses a bound row without
/// one. With no argument it creates a fresh identity: signing in a running
/// app's identity leaves that app holding no credential.
pub async fn sign_in(user: Option<&str>) -> Result<()> {
    let pool = pool().await?;
    let id = if let Some(id) = user {
        parse_user(id)?
    } else {
        let id: Uuid =
            sqlx::query_scalar("insert into users (id) values (gen_random_uuid()) returning id")
                .fetch_one(&pool)
                .await?;
        println!("no user id given, created a fresh identity: {id}");
        id
    };

    // `coalesce` keeps an already-bound row on the Apple account it has —
    // rebinding would strand whatever is filed under the old one.
    let bound: Option<String> = sqlx::query_scalar(
        "update users set apple_user_id = coalesce(apple_user_id, 'dev.' || id) \
         where id = $1 returning apple_user_id",
    )
    .bind(id)
    .fetch_optional(&pool)
    .await?;
    let Some(bound) = bound else {
        bail!("no user with id {id}");
    };

    let credential = mint_credential()?;
    sqlx::query("insert into user_sessions (token_hash, user_id) values ($1, $2)")
        .bind(credential_hash(&credential).to_vec())
        .bind(id)
        .execute(&pool)
        .await?;

    println!("signed {id} in as {bound}");
    println!();
    println!("  ond-user-id: {id}");
    println!("  ond-session-credential: {credential}");
    println!();
    println!(
        "Both headers on every request from now on — the id alone is refused once a row is bound."
    );
    println!("Pair with `mise run dev:plus {id}` to reach önd+.");
    Ok(())
}

/// Base64url without padding over 32 random bytes, matching
/// `SessionCredential::mint` in crates/api — the server hashes the secret
/// exactly as presented, so any other encoding hashes to something no
/// request can reproduce.
fn mint_credential() -> Result<String> {
    let mut bytes = [0u8; 32];
    SystemRandom::new()
        .fill(&mut bytes)
        .ok()
        .context("read the system's random source")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

/// SHA-256 of the secret's ASCII bytes — the stored form `CredentialHash::of`
/// compares against, not a hash of the raw bytes behind the encoding.
fn credential_hash(credential: &str) -> [u8; 32] {
    let mut hash = [0u8; 32];
    hash.copy_from_slice(digest(&SHA256, credential.as_bytes()).as_ref());
    hash
}

fn parse_user(id: &str) -> Result<Uuid> {
    id.parse().with_context(|| format!("{id} is not a user id"))
}

async fn pool() -> Result<PgPool> {
    let url = std::env::var("DATABASE_URL").context("DATABASE_URL is unset — run through mise")?;
    PgPool::connect(&url)
        .await
        .context("connect to the dev database — is `mise run dev:db` up?")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pins the encoding contract with `SessionCredential::mint`: 32 bytes,
    /// base64url alphabet, no padding — 43 characters exactly.
    #[test]
    fn a_minted_credential_matches_the_server_encoding() {
        let credential = mint_credential().unwrap();
        assert_eq!(credential.len(), 43);
        assert!(!credential.ends_with('='));
        assert!(
            credential
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        );
    }

    /// The stored form hashes the encoded string, not the bytes behind it.
    #[test]
    fn the_hash_covers_the_presented_string() {
        let expected = digest(&SHA256, b"abc");
        assert_eq!(credential_hash("abc"), expected.as_ref());
    }
}
