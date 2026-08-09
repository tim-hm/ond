//! Compact-JWS segment parsing — the part of verifying a signed token that is
//! the same whoever signed it.
//!
//! Outside `features/` because two of them consume it, on paths that must not
//! drift: `account/verifier/apple.rs` takes apart Apple's identity token to
//! decide a sign-in, and `entitlement/verifier/appstore.rs` takes apart a
//! signed transaction to decide who holds a paid entitlement. Each carried its
//! own copy of this until a fix to one was a fix the other silently missed.
//!
//! Only the taking-apart lives here. What the segments *mean* — which header
//! fields matter, which claims decide anything, and above all how the
//! signature is checked — stays with each verifier, because those genuinely
//! differ: one verifies against Apple's published RSA keys, the other walks an
//! x5c chain to Apple's root.

use serde::Deserialize;

/// A compact JWS that could not be taken apart.
///
/// One shape rather than a variant per cause: every caller folds this into its
/// own `VerificationError::Malformed`, and the message is the whole of what
/// travels.
#[derive(Debug)]
pub struct MalformedJws(pub String);

/// One token, taken apart and nothing more — decoded, not verified. The
/// header and payload are read through the typed methods below; the signature
/// is raw bytes for the caller's crypto check.
#[derive(Debug)]
pub struct Segments<'a> {
    /// The first two segments and the dot between them, verbatim — re-encoding
    /// the decoded parts would produce different bytes and a signature that
    /// never verifies.
    pub signing_input: &'a [u8],
    pub signature: Vec<u8>,
    header: Vec<u8>,
    payload: Vec<u8>,
}

impl Segments<'_> {
    /// Reads the header as the JSON shape the caller expects of it.
    pub fn header_json<T: for<'de> Deserialize<'de>>(&self) -> Result<T, MalformedJws> {
        decode_json(&self.header, "header")
    }

    /// Reads the payload as the JSON shape the caller expects of it.
    pub fn payload_json<T: for<'de> Deserialize<'de>>(&self) -> Result<T, MalformedJws> {
        decode_json(&self.payload, "payload")
    }
}

/// Splits a compact JWS into its three segments and decodes each.
pub fn split(token: &str) -> Result<Segments<'_>, MalformedJws> {
    let mut parts = token.split('.');
    let (Some(header), Some(payload), Some(signature), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(MalformedJws(
            "a compact JWS is exactly three dot-separated segments".to_owned(),
        ));
    };

    let signing_input_len = header.len() + 1 + payload.len();

    Ok(Segments {
        signing_input: &token.as_bytes()[..signing_input_len],
        signature: decode_segment(signature, "signature")?,
        header: decode_segment(header, "header")?,
        payload: decode_segment(payload, "payload")?,
    })
}

fn decode_json<T: for<'de> Deserialize<'de>>(
    segment: &[u8],
    name: &str,
) -> Result<T, MalformedJws> {
    serde_json::from_slice(segment).map_err(|error| {
        MalformedJws(format!(
            "the {name} is not the JSON expected of it: {error}"
        ))
    })
}

fn decode_segment(segment: &str, name: &str) -> Result<Vec<u8>, MalformedJws> {
    use base64::Engine as _;

    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(segment)
        .map_err(|error| MalformedJws(format!("the {name} is not base64url: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Three segments, and only three. A token missing its signature must fail
    /// as malformed rather than reaching a path that treats an absent
    /// signature as an empty one.
    #[test]
    fn a_token_that_is_not_three_segments_is_malformed() {
        for token in ["", "not-a-jws", "one.two", "one.two.three.four"] {
            assert!(split(token).is_err(), "{token}");
        }
    }
}
