//! Compact-JWS segment parsing — the part of verifying a signed token that is
//! the same whoever signed it. Outside `features/` because the account and
//! entitlement verifiers both consume it, and each carried its own copy until
//! a fix to one was a fix the other silently missed. Only the taking-apart
//! lives here; which claims decide anything and how the signature is checked stay with each verifier.

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

    let signing_input_len = header
        .len()
        .checked_add(1)
        .and_then(|length| length.checked_add(payload.len()))
        .ok_or_else(|| MalformedJws("the signing input length overflowed".to_owned()))?;
    let signing_input = token
        .as_bytes()
        .get(..signing_input_len)
        .ok_or_else(|| MalformedJws("the signing input is not present in the token".to_owned()))?;

    Ok(Segments {
        signing_input,
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

    #[test]
    fn the_signing_input_is_exactly_the_first_two_segments() {
        let segments = split("e30.e30.AA").expect("three base64url segments");

        assert_eq!(segments.signing_input, b"e30.e30");
    }
}
