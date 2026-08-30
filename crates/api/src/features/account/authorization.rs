//! The single-use ceremony that binds an Apple identity token to one caller
//! and one account action.

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chrono::{DateTime, TimeDelta, Timelike as _, Utc};
use ring::digest::{self, SHA256};
use ring::rand::{SecureRandom as _, SystemRandom};

use super::errors::AccountError;

const NONCE_BYTES: usize = 32;
const CHALLENGE_LIFETIME: TimeDelta = TimeDelta::minutes(5);

/// The account action an Apple authorization may approve. Mirrors the
/// `apple_authorization_purpose` Postgres enum, and binds as one rather than
/// as text through a `::text::` cast — the one way every other enum in the
/// crate reaches its column. Labels are spelled per variant, as
/// `LeaderboardBoard` does, so renaming a variant cannot rename a stored value.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "apple_authorization_purpose")]
pub enum AuthorizationPurpose {
    /// Bind or recover an Apple account.
    #[sqlx(rename = "SIGN_IN")]
    SignIn,
    /// Permanently erase an Apple-bound account.
    #[sqlx(rename = "DELETE_ACCOUNT")]
    DeleteAccount,
}

/// A freshly minted raw nonce and the digest the database keeps.
pub struct AuthorizationChallenge {
    raw: String,
    hash: AuthorizationNonceHash,
    expires_at: DateTime<Utc>,
}

impl AuthorizationChallenge {
    /// Mints 256 random bits and derives the only form retained server-side.
    pub fn mint() -> Result<Self, AccountError> {
        let mut bytes = [0_u8; NONCE_BYTES];
        SystemRandom::new()
            .fill(&mut bytes)
            .map_err(|_| AccountError::Randomness)?;

        let raw = URL_SAFE_NO_PAD.encode(bytes);
        let hash = AuthorizationNonceHash::of_raw(&raw);
        let expires_at = Utc::now() + CHALLENGE_LIFETIME;
        let expires_at =
            expires_at - TimeDelta::nanoseconds(i64::from(expires_at.nanosecond() % 1_000));
        Ok(Self {
            raw,
            hash,
            expires_at,
        })
    }

    /// The digest persisted until the challenge is consumed or replaced.
    pub const fn hash(&self) -> &AuthorizationNonceHash {
        &self.hash
    }

    /// The absolute database and client expiry for this ceremony.
    pub const fn expires_at(&self) -> DateTime<Utc> {
        self.expires_at
    }

    /// The raw nonce returned to the one client that requested it.
    pub fn into_raw(self) -> String {
        self.raw
    }
}

/// The SHA-256 of a raw challenge, as persisted and as Apple returns it in the
/// signed token's `nonce` claim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthorizationNonceHash([u8; digest::SHA256_OUTPUT_LEN]);

impl AuthorizationNonceHash {
    fn of_raw(raw: &str) -> Self {
        let digest = digest::digest(&SHA256, raw.as_bytes());
        let mut bytes = [0_u8; digest::SHA256_OUTPUT_LEN];
        bytes.copy_from_slice(digest.as_ref());
        Self(bytes)
    }

    /// Parses Apple's lowercase hexadecimal nonce claim without accepting a
    /// second textual representation of the same digest.
    pub fn from_apple_claim(claim: &str) -> Result<Self, InvalidAuthorizationNonce> {
        let encoded = claim.as_bytes();
        if encoded.len() != digest::SHA256_OUTPUT_LEN * 2 {
            return Err(InvalidAuthorizationNonce);
        }

        let mut bytes = [0_u8; digest::SHA256_OUTPUT_LEN];
        for (index, pair) in encoded.chunks_exact(2).enumerate() {
            bytes[index] = (hex_nibble(pair[0])? << 4) | hex_nibble(pair[1])?;
        }

        Ok(Self(bytes))
    }

    /// The bytes compared by Postgres.
    pub const fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

fn hex_nibble(byte: u8) -> Result<u8, InvalidAuthorizationNonce> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        _ => Err(InvalidAuthorizationNonce),
    }
}

/// Apple's nonce claim was not one lowercase SHA-256 digest.
#[derive(Debug, Clone, Copy, thiserror::Error)]
#[error("`nonce` is not a lowercase SHA-256 digest")]
pub struct InvalidAuthorizationNonce;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_challenge_is_distinct_and_keeps_only_a_digest() {
        let first = AuthorizationChallenge::mint().expect("a random source");
        let second = AuthorizationChallenge::mint().expect("a random source");

        assert_ne!(first.raw, second.raw);
        assert_ne!(first.hash.as_bytes(), second.hash.as_bytes());
        assert_eq!(first.raw.len(), 43, "256 base64url bits without padding");
        let lifetime = first.expires_at - Utc::now();
        assert!(lifetime <= CHALLENGE_LIFETIME);
        assert!(lifetime > TimeDelta::minutes(4));
    }

    #[test]
    fn apple_claims_accept_exactly_lowercase_sha256() {
        let valid = "0123456789abcdef".repeat(4);
        assert!(AuthorizationNonceHash::from_apple_claim(&valid).is_ok());

        for invalid in [
            "0".repeat(63),
            "0".repeat(65),
            "G".repeat(64),
            "A".repeat(64),
        ] {
            assert!(AuthorizationNonceHash::from_apple_claim(&invalid).is_err());
        }
    }
}
