//! `AssistantService`, over the wire the iOS client uses, against a scripted
//! model — no network and no credentials. The seam in
//! `features::assistant::model` makes everything worth testing here
//! deterministic; the only code not reached is the thin layer in `bedrock`
//! that turns a `ModelRequest` into a signed Bedrock call.

mod chat;
mod fixtures;
mod quota;
mod recommendation;
