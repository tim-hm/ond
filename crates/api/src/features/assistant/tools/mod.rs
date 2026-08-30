//! The three tools Chat may declare and the one dispatcher that turns model
//! calls into validated wire payloads. Each tool owns its stable name,
//! schema, input vocabulary, validation, and payload conversion; [`dispatch`]
//! is the only cross-tool match.

mod bolt;
mod dispatch;
mod exercise;
mod saved_exercise;

pub(super) use self::dispatch::{dispatch, specs};
