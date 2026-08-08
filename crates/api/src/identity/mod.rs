//! Who is calling, resolved once for every gRPC request.
//!
//! The whole of the auth model on the request path: a client generates a UUID on
//! first launch, keeps it in its Keychain, and sends it on every RPC. Possession
//! of the id *is* the claim — there is no token, no signature, and nothing here
//! pretends otherwise. That is a deliberate trade (anonymous, no account,
//! nothing sensitive stored), and it holds for as long as the device does.
//!
//! The credential that survives a change of device attaches through
//! `features::account`, which writes `users.apple_user_id`. Signing in can
//! therefore *change* which id a client sends: an Apple account that already has
//! a row means the caller's anonymous identity is folded into it and then
//! deleted, so a row this module created can stop existing between one request
//! and the next. What moves, what is summed, and what is left behind is
//! documented in full on `features::account::repository::merge`.
//!
//! Top-level rather than inside a feature because it sits *under* all of them:
//! the row exists before any feature is interested in it, `profile` is one
//! consumer and `journey` is another, and a layer that imported a feature would
//! invert the dependency this module's callers rely on.
//!
//! A directory rather than one file so that its two queries live in a
//! `repository.rs` like every other query in the crate — see
//! docs/code-structure.md.

mod middleware;
mod repository;

pub use middleware::{USER_ID_HEADER, UserId, require, resolve};
