//! Breathing facts `migrate` and `api` must agree on; neither may depend on the
//! other, so the numbers live here once. The blackout rule: fast breathing
//! removes carbon dioxide, so a timed hold after it can make a person faint. A
//! safe hold is short, or the person ends it. `migrate` applies the rule to the
//! seeded catalogue and `api` to an authored technique; both are needed.

/// Shorter than this, one breath in and out is over-breathing. Four seconds is
/// fifteen breaths a minute, the top of the usual resting range. It is a cycle
/// length, not a rate: `60_000 / cycle > 15` rounds to sixteen and lets a
/// 3.9-second cycle through.
pub const FAST_BREATHING_CYCLE_MS: i32 = 4_000;

/// The longest a hold may be timed for in a technique that breathes fast
/// anywhere in it. Fifteen seconds is the Wim Hof round's recovery hold and
/// twenty is the top of its dial. Past that, a countdown is a target.
pub const TIMED_HOLD_CEILING_MS: i32 = 20_000;

/// Whether a cycle this long counts as over-breathing.
///
/// Pass the whole cycle, holds included. A hold inside the repeating pattern
/// makes the rate slow, and one quick breath every forty seconds accumulates
/// carbon dioxide rather than washing it out.
#[must_use]
pub const fn breathes_fast(cycle_ms: i32) -> bool {
    cycle_ms < FAST_BREATHING_CYCLE_MS
}

/// Whether a hold timed to this length is a target rather than a recovery beat.
///
/// Ask it of the longest the hold can be dialled to, never the curated default:
/// a hold that only becomes a feat once somebody turns it up is still a feat
/// the app offered them.
#[must_use]
pub const fn is_a_timed_target(hold_ms: i32) -> bool {
    hold_ms > TIMED_HOLD_CEILING_MS
}

#[cfg(test)]
mod tests {
    use super::{breathes_fast, is_a_timed_target};

    /// Both boundaries, from both sides. A rule stated as a constant is read by
    /// two crates and applied by neither of them directly — so the one thing
    /// worth pinning is which side of each threshold is the safe one.
    #[test]
    fn the_thresholds_are_inclusive_of_the_safe_side() {
        assert!(breathes_fast(3_999));
        assert!(!breathes_fast(4_000), "four seconds a cycle is not fast");

        assert!(is_a_timed_target(20_001));
        assert!(
            !is_a_timed_target(20_000),
            "the Wim Hof recovery dial's own top is a beat, not a feat"
        );
    }
}
