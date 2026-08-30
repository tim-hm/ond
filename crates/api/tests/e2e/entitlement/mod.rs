//! `EntitlementService`, over the wire the iOS client uses, against a scripted
//! App Store verifier. No Apple-signed material anywhere: a real
//! `jwsRepresentation` needs Apple's private key, and one captured from a
//! sandbox purchase goes stale when its certificate chain rotates. The real
//! verifier is pinned by its unit tests; what the *server* does with a verified transaction is pinned here.

mod access;
mod fixtures;
mod ownership;
mod purchase;
mod refunds;

use self::fixtures::*;
