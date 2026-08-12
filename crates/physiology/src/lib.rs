//! What a body does, stated once, for the two crates that have to answer to it.
//!
//! Everything here is a fact about breathing rather than about this system: no
//! schema, no wire format, no product decision. That is what makes it safe to
//! be a leaf. `migrate` runs before the schema exists and `api` is the server
//! that comes after it, so neither may depend on the other — and each was
//! therefore keeping its own copy of the blackout rule's numbers, pinned to the
//! other by a test whose only job was to notice them drifting apart.
//!
//! A dependency with nothing in it is cheaper than that test. Both crates
//! depend on this one, the numbers exist once, and the tripwire is gone along
//! with the thing it was watching.
//!
//! # The blackout rule
//!
//! Hyperventilation followed by a measured breath-hold is *the* documented way
//! to faint doing breathwork. Over-breathing blows off the carbon dioxide that
//! would otherwise make somebody breathe, so the urge to inhale arrives after
//! the oxygen has gone rather than before it — and a person counting down to a
//! number they mean to reach will push past the point where they would have
//! stopped on their own.
//!
//! What the rule forbids is therefore a *target*: a clock-driven hold, in a
//! technique that breathes fast anywhere in it, long enough that reaching the
//! end of it is an achievement. The two ways out are the two safe designs —
//! keep the hold to a recovery beat, or let the person end it themselves so
//! there is nothing to reach.
//!
//! It is applied in two places over two different shapes. `migrate` checks the
//! curated catalogue at seed time; `api` refuses a technique somebody composes.
//! Neither can be dropped: the catalogue is safe today because somebody
//! checked, and an authored technique has no curator at all.

/// Shorter than this, one breath in and out is over-breathing rather than
/// breathing slowly.
///
/// Four seconds is fifteen breaths a minute, the top of the usual resting
/// range. A cycle length rather than a rate, because a rate means dividing —
/// and integer division silently moves the line, so `60_000 / cycle > 15`
/// actually sits at sixteen and lets a 3.9-second cycle through the rule its
/// own doc comment promised to apply to it. That was a real defect, found in
/// review; the constant is stated this way so it cannot come back.
pub const FAST_BREATHING_CYCLE_MS: i32 = 4_000;

/// The longest a hold may be timed for in a technique that breathes fast
/// anywhere in it.
///
/// Fifteen seconds is the Wim Hof round's recovery hold and twenty is the top
/// of its dial; past that a countdown is something to get through rather than
/// a beat to settle on.
pub const TIMED_HOLD_CEILING_MS: i32 = 20_000;

/// Whether a cycle this long counts as over-breathing.
///
/// The comparison, not just the number, because which side of the line the
/// boundary falls on is exactly what a second copy gets wrong — and a rule
/// that quietly stopped applying at its own threshold would look identical to
/// one that worked.
///
/// The whole cycle, holds included, is what the caller must pass: a hold inside
/// the repeating pattern is what makes the rate slow, and one quick breath
/// every forty seconds accumulates carbon dioxide rather than washing it out,
/// which is the opposite of this hazard.
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
