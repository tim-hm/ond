//! `AccountService`, over the wire the iOS client uses, against a scripted
//! Sign in with Apple verifier. Nothing Apple signed anywhere: a real identity
//! token needs Apple's private key and checking one needs a network fetch, so
//! this is the only shape the suite could have. The real verifier is pinned by
//! its unit tests; what the *server* does with a proven account is pinned here.

mod authorization;
mod deletion;
mod fixtures;
mod merge;
mod sign_in;

use self::fixtures::*;
