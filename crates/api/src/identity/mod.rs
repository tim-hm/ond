//! Who is calling, resolved once for every gRPC request, and what proves it.
//!
//! The whole of the auth model on the request path, and it has two halves
//! because the people using this app do.
//!
//! **Anonymous.** A client generates a UUID on first launch, keeps it in its
//! Keychain, and sends it on every RPC. Possession of the id *is* the claim.
//! That is a deliberate trade — no account, nothing sensitive stored, and the
//! app works before anyone has been asked for anything — and it holds for as
//! long as the device does.
//!
//! **Signed in.** Once a row carries an `apple_user_id` the trade changes on
//! both sides. The row is now a history its owner can be handed back on another
//! device, which is what makes it worth stealing — and that same recovery is
//! what makes refusing a caller affordable, because a bound identity has a way
//! back in that an anonymous one does not. So a verified sign-in mints a
//! credential — 256 random bits, returned once, stored only as a SHA-256 — and
//! from then on the row proves that binding on every request. [`resolve`] fails
//! closed for a bound row and asks an unbound one for nothing.
//!
//! `features::account` is what moves a row between the two: it writes
//! `users.apple_user_id` and calls [`start_session`] and [`end_session`] here,
//! because the credential belongs to the identity rather than to that feature.
//! Signing in can also *change* which id a client sends — an Apple account that
//! already has a row means the caller's anonymous identity is folded into it and
//! then deleted, so a row this module created can stop existing between one
//! request and the next. What moves, what is summed, and what is left behind is
//! documented in full on `features::account::repository::merge`.
//!
//! Top-level rather than inside a feature because it sits *under* all of them:
//! the row exists before any feature is interested in it, `profile` is one
//! consumer and `journey` is another, and a layer that imported a feature would
//! invert the dependency this module's callers rely on.
//!
//! A directory rather than one file so that its queries live in a
//! `repository.rs` like every other query in the crate — see
//! docs/code-structure.md.

mod credential;
mod middleware;
mod repository;

pub use credential::{CredentialHash, SessionCredential, SessionError};
pub use middleware::{
    SESSION_CREDENTIAL_HEADER, SupportReference, USER_ID_HEADER, UserId, presented_credential,
    require, resolve,
};
pub use repository::{end_session, start_session};
