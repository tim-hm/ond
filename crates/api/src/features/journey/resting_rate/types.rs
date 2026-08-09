//! What the resting-rate history folds down to.

/// The resting-rate history folded to the three numbers a coach can use: the
/// slowest this person has measured, where they are now, and how much evidence
/// there is for either.
///
/// Unwindowed, like [`super::super::bolt::types::BoltSnapshot`] beside it: a
/// slowest rate is a personal record rather than a recent-form figure.
///
/// "Lowest" is the personal best here, which is the one place this measurement
/// reads backwards from the pause. A resting breath that has slowed is the
/// direction practice moves it — see `super::service` for the evidence that
/// says so.
#[derive(Debug, PartialEq, Eq)]
pub struct RestingRateSnapshot {
    /// Slowest resting rate ever measured, in breaths a minute.
    pub lowest: u32,
    /// The most recently measured rate, in breaths a minute.
    pub latest: u32,
    /// How many measurements the caller has ever recorded.
    pub count: u32,
}
