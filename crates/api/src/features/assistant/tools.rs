//! The three tools Chat may declare and the one dispatcher that turns model
//! calls into validated wire payloads. Each tool owns its stable name,
//! schema, input vocabulary, validation, and payload conversion; [`dispatch`]
//! is the only cross-tool match.

mod bolt;
mod dispatch;
mod exercise;
mod saved_exercise;

pub(super) use self::dispatch::{dispatch, specs};

fn clamped(value: i64, ceiling: i32) -> Option<u32> {
    u32::try_from(value.clamp(1, i64::from(ceiling))).ok()
}

/// Seconds as wire milliseconds inside an inclusive range.
///
/// The cast is safe after the f64 clamp into bounds already represented by
/// `i32`; the standard library has no checked float-to-integer conversion.
#[allow(clippy::cast_possible_truncation)]
fn clamped_ms(seconds: f64, min: i32, max: i32) -> i32 {
    (seconds * 1000.0)
        .round()
        .clamp(f64::from(min), f64::from(max)) as i32
}
