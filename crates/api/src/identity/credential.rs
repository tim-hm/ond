//! The secret a signed-in caller presents, and the hash the server keeps.
//! Opaque rather than signed: `resolve` already makes a database round trip on
//! every identified request, a signing key would be a new secret, and a row
//! revokes with a `DELETE` — which sign-out and `DeleteAccount` need and a
//! signed token cannot do without a revocation list, the row by a longer route.

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use ring::digest::{self, SHA256};
use ring::rand::{SecureRandom as _, SystemRandom};

/// How much randomness a credential carries.
///
/// The credential is guessed or it is not; there is no other way in, because
/// nothing about it is derived from anything an attacker can see. 256 bits puts
/// guessing out of reach permanently rather than for a while.
const SECRET_BYTES: usize = 32;

/// Why a caller could not be given a credential. Both variants are this
/// server's fault and both travel to the client as `internal`, so the split
/// exists for the log rather than for the response — "the database refused"
/// and "the machine has no randomness" are diagnosed in different places.
#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    /// The operating system's random source refused. Returned rather than
    /// panicked, per the workspace lint policy. Never falls back to a weaker
    /// source — a credential nobody can be sure is unguessable is worse than
    /// a sign-in that failed and can be retried.
    #[error("the system random source is unavailable")]
    Randomness,

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
}

/// A freshly minted credential, on its way to the one client that will ever
/// see it. Owns the secret and is consumed by [`Self::into_secret`], so the
/// value cannot be read twice by accident and cannot be logged without saying
/// so in the call.
pub struct SessionCredential {
    secret: String,
    hash: CredentialHash,
}

impl SessionCredential {
    /// Mints one from the system's random source.
    pub fn mint() -> Result<Self, SessionError> {
        let mut bytes = [0u8; SECRET_BYTES];
        SystemRandom::new()
            .fill(&mut bytes)
            .map_err(|_| SessionError::Randomness)?;

        let secret = URL_SAFE_NO_PAD.encode(bytes);
        let hash = CredentialHash::of(&secret);

        Ok(Self { secret, hash })
    }

    /// What the database stores.
    pub const fn hash(&self) -> &CredentialHash {
        &self.hash
    }

    /// The secret itself, for the one response that carries it.
    pub fn into_secret(self) -> String {
        self.secret
    }
}

/// The SHA-256 of a credential — the only form of it this server keeps.
/// Compared by the database with `=`, which is safe where a password hash
/// comparison is not: a timing difference leaks a prefix of the *hash*, and
/// there is no route from a hash prefix back to the secret that produced it.
pub struct CredentialHash([u8; digest::SHA256_OUTPUT_LEN]);

impl CredentialHash {
    /// Hashes a credential exactly as presented.
    ///
    /// No trimming and no case folding: the client echoes back the bytes it was
    /// given, so anything that "helpfully" repaired a value here would accept a
    /// credential nobody minted.
    pub fn of(presented: &str) -> Self {
        let digest = digest::digest(&SHA256, presented.as_bytes());
        let mut bytes = [0u8; digest::SHA256_OUTPUT_LEN];
        bytes.copy_from_slice(digest.as_ref());

        Self(bytes)
    }

    pub const fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Two mints are two credentials. A generator that had somehow been wired to
    /// a fixed seed would hand every signed-in person the same secret, and every
    /// other test here would still pass.
    #[test]
    fn every_credential_is_its_own() {
        let first = SessionCredential::mint().expect("a random source");
        let second = SessionCredential::mint().expect("a random source");

        assert_ne!(first.hash().as_bytes(), second.hash().as_bytes());
        assert_ne!(first.into_secret(), second.into_secret());
    }

    /// The stored hash is the one a later request reproduces from the secret it
    /// presents. This is the whole of the check `resolve` makes, and it is a
    /// pure function on both sides of the wire — so it is worth pinning without
    /// a database.
    #[test]
    fn a_presented_secret_hashes_to_what_was_stored() {
        let credential = SessionCredential::mint().expect("a random source");
        let stored = credential.hash().as_bytes().to_vec();

        assert_eq!(
            CredentialHash::of(&credential.into_secret()).as_bytes(),
            stored
        );
    }

    /// The secret travels in an HTTP header, so it has to survive one: base64url
    /// with no padding is header-safe by construction, and a credential carrying
    /// a byte a header cannot is a sign-in that works until somebody's proxy
    /// disagrees.
    #[test]
    fn a_credential_is_a_value_a_header_can_carry() {
        let secret = SessionCredential::mint()
            .expect("a random source")
            .into_secret();

        assert!(
            secret
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'),
            "`{secret}` is not base64url"
        );
    }
}
