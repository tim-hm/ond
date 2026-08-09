//! Conversions every feature performs on the proto boundary.
//!
//! Crate-level because the rules are the schema's rather than any one
//! feature's: a `CHECK`-constrained column that fails to narrow is corrupt
//! data whichever service is serving it. The error still has to speak in the
//! serving feature's vocabulary, which is what [`Unrepresentable`]'s `From`
//! impls carry — the same arrangement `MalformedJws` has with the two
//! verifiers, and what keeps thirteen call sites free of `map_err`.

use std::fmt::Display;

use chrono::{DateTime, Utc};

/// What a failed narrowing carries: the message a feature wraps into its own
/// corrupt-data case via a `From` impl beside its `Status` mapping.
#[derive(Debug)]
pub struct Unrepresentable(pub String);

/// Narrows a counted value to the width the wire states it in.
///
/// The schema's `CHECK`s make a negative value unreachable and no fold can
/// overflow the integer it is read into, so a value that does not fit is
/// corrupt data. Failing names the column; the alternatives this replaced —
/// `unwrap_or(0)` on a streak, `unwrap_or(u32::MAX)` on a session count — put
/// a number in front of somebody indistinguishable from one they earned.
///
/// Generic in both directions rather than written once per pair. The counts
/// arrive as `i32`, `i64`, `u64` and `usize` depending on whether they were
/// summed, counted or measured, and land on `u32` or `u64` depending on the
/// field: a fixed signature would push a widening cast onto every call site,
/// and a cast is the thing this exists to remove.
pub fn counted<T, V>(field: &str, value: V) -> Result<T, Unrepresentable>
where
    V: TryInto<T> + Copy + Display,
{
    value
        .try_into()
        .map_err(|_| Unrepresentable(format!("`{field}` is `{value}`, which is not a count")))
}

/// [`counted`], additionally refusing zero — for the columns the schema
/// constrains `CHECK (… > 0)`: every catalogue and authored duration, cycle
/// and round.
///
/// Zero is refused here rather than served because the client refuses it
/// anyway — a zero duration comes back as a whole list the app cannot read —
/// and naming the row is the more useful of the two refusals. `unsigned_abs`
/// is not an option in either helper: it would serve `-4000` back as a
/// plausible `4000`.
pub fn positive<T, V>(field: &str, value: V) -> Result<T, Unrepresentable>
where
    V: TryInto<T> + Copy + Display,
    T: Into<u64> + Copy,
{
    let count: T = counted(field, value)?;
    if count.into() == 0 {
        return Err(Unrepresentable(format!(
            "`{field}` is `{value}`, which is not a positive count"
        )));
    }
    Ok(count)
}

/// An instant for the wire, which cannot fail.
///
/// The subsecond nanoseconds are clamped rather than checked: a leap second
/// reports more than a billion of them, which the proto type cannot carry, and
/// losing at most that one second is the right answer for a value being drawn
/// on a history strip or an entitlement row.
pub fn timestamp_to_proto(instant: DateTime<Utc>) -> prost_types::Timestamp {
    prost_types::Timestamp {
        seconds: instant.timestamp(),
        nanos: i32::try_from(instant.timestamp_subsec_nanos()).unwrap_or(999_999_999),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A count the domain cannot represent has to fail the call rather than
    /// arrive as a plausible number. The old shapes — a zeroed streak, a
    /// session count of four billion — are the caller's own figures, which are
    /// the ones they are most likely to believe.
    #[test]
    fn an_unrepresentable_count_fails_rather_than_being_rewritten() {
        assert_eq!(counted::<u32, _>("sessions", 42_i64).expect("in range"), 42);
        assert!(counted::<u32, _>("sessions", -1_i32).is_err());
        assert!(counted::<u32, _>("sessions", i64::from(u32::MAX) + 1).is_err());
        assert!(counted::<u64, _>("breaths", -1_i64).is_err());
    }

    /// Zero passes `counted` — a streak of nothing is a real streak — and
    /// fails `positive`, because the columns routed through it carry a
    /// `CHECK (… > 0)` and a zero from one of them is corrupt data.
    #[test]
    fn zero_is_a_count_but_not_a_positive_one() {
        assert_eq!(
            counted::<u32, _>("sessions", 0_i64).expect("a real total"),
            0
        );
        assert!(positive::<u32, _>("phase duration", 0_i32).is_err());
        assert_eq!(
            positive::<u32, _>("stage cycles", 10_i32).expect("in range"),
            10
        );
    }
}
