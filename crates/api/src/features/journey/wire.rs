//! The journey-specific half of the wire boundary: time.
//!
//! Sessions carry instants, and the caller's UTC offset decides which local
//! day each one falls in. Both conversions here are fallible, and deliberately
//! so — these are the caller's own dates, and a guessed instant is a day
//! somebody reads as theirs. The arithmetic half — narrowing the aggregates
//! read back signed — lives in [`crate::wire`], because every feature does it
//! by the same rule.

use chrono::{DateTime, Utc};

use super::errors::JourneyError;

/// UTC offsets in use run from -12:00 to +14:00. Anything outside is not a time
/// zone.
const MIN_UTC_OFFSET_MINUTES: i32 = -12 * 60;
const MAX_UTC_OFFSET_MINUTES: i32 = 14 * 60;

/// And every one of them is a whole number of quarter-hours — the odd ones,
/// Kathmandu at +05:45 and Chatham at +12:45, are still multiples of fifteen.
const UTC_OFFSET_STEP_MINUTES: i32 = 15;

/// Refuses an offset no time zone uses.
///
/// A client bug rather than a malicious value, but accepting it would silently
/// shift somebody's calendar days and therefore their streak.
///
/// The quarter-hour rule is also what keeps the leaderboard snapshot finite.
/// The streak board is materialised once per day boundary it is asked for
/// (`0013_leaderboard_snapshot.sql`), so the set of offsets this admits is the
/// set of copies that can exist — a hundred and five of them, rather than one
/// per minute of the range.
pub fn validated_offset(minutes: i32) -> Result<i32, JourneyError> {
    if (MIN_UTC_OFFSET_MINUTES..=MAX_UTC_OFFSET_MINUTES).contains(&minutes)
        && minutes % UTC_OFFSET_STEP_MINUTES == 0
    {
        return Ok(minutes);
    }

    Err(JourneyError::Invalid(format!(
        "`utc_offset_minutes` must be a multiple of {UTC_OFFSET_STEP_MINUTES} between {MIN_UTC_OFFSET_MINUTES} and {MAX_UTC_OFFSET_MINUTES}"
    )))
}

/// `google.protobuf.Timestamp` admits values no instant can hold — a negative
/// nanosecond count, a second count past the end of the calendar — so the
/// conversion is fallible and says which field failed.
pub fn timestamp_from_proto(
    stamp: &prost_types::Timestamp,
    field: &str,
) -> Result<DateTime<Utc>, JourneyError> {
    u32::try_from(stamp.nanos)
        .ok()
        .and_then(|nanos| DateTime::from_timestamp(stamp.seconds, nanos))
        .ok_or_else(|| JourneyError::Invalid(format!("`{field}` is not a valid timestamp")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::timestamp_to_proto;

    /// The round trip a recent session makes on the way back out. Sub-second
    /// precision matters because a session at 23:59:59.9 local is the difference
    /// between a streak that held and one that paused.
    #[test]
    fn a_timestamp_survives_the_round_trip() {
        let instant =
            DateTime::from_timestamp(1_777_000_000, 123_456_789).expect("a representable instant");

        assert_eq!(
            timestamp_from_proto(&timestamp_to_proto(instant), "started_at")
                .expect("a converted timestamp is valid"),
            instant
        );
    }

    /// A negative nanosecond count is representable on the wire and is not an
    /// instant. Decoding it as one would put a session at an arbitrary moment.
    #[test]
    fn an_impossible_timestamp_fails_rather_than_being_guessed_at() {
        let malformed = prost_types::Timestamp {
            seconds: 1_777_000_000,
            nanos: -1,
        };

        assert!(matches!(
            timestamp_from_proto(&malformed, "started_at"),
            Err(JourneyError::Invalid(_))
        ));
    }

    /// The offsets that exist run from -12:00 to +14:00 and are whole
    /// quarter-hours. Anything else is a client bug, and accepting it would
    /// silently shift somebody's calendar days — and mint a leaderboard
    /// snapshot key no time zone will ever ask for again.
    #[test]
    fn only_real_utc_offsets_are_accepted() {
        for minutes in [MIN_UTC_OFFSET_MINUTES, 0, 60, 345, MAX_UTC_OFFSET_MINUTES] {
            assert!(validated_offset(minutes).is_ok());
        }
        for minutes in [MIN_UTC_OFFSET_MINUTES - 1, MAX_UTC_OFFSET_MINUTES + 1, 7] {
            assert!(matches!(
                validated_offset(minutes),
                Err(JourneyError::Invalid(_))
            ));
        }
    }
}
