//! What the resting-rate history folds down to.

/// The resting-rate history folded to the numbers a coach can use.
///
/// Unwindowed, like [`super::super::bolt::types::BoltSnapshot`]: a slowest rate
/// is a personal record, not recent form. "Lowest" is the personal best here,
/// the one place this measurement reads backwards from the pause.
#[derive(Debug, PartialEq, Eq)]
pub struct RestingRateSnapshot {
    /// Slowest resting rate ever measured, in breaths a minute.
    pub lowest: u32,
    /// The most recently measured rate, in breaths a minute.
    pub latest: u32,
    /// How many measurements the caller has ever recorded.
    pub count: u32,
}
