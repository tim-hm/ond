//! `AssistantService`, over the wire the iOS client uses, against a scripted
//! model.
//!
//! No network and no credentials. The seam in `features::assistant::model`
//! exists so that everything worth testing here — validation, quota, the
//! breaker, the fallback, and the streaming frames — is testable
//! deterministically; the only code these tests do not reach is the thin layer
//! in `bedrock` that turns a `ModelRequest` into a signed Bedrock call.
//!
//! Split one file per RPC, plus the spend controls both share. What they
//! build their world out of is [`fixtures`].

mod chat;
mod fixtures;
mod quota;
mod recommendation;
