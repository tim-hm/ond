//! Refuses a start time no session could have. The bounds guard streaks, not
//! storage: a session dated next year holds a current streak open and nothing
//! recorded later can close it. Nothing here reads the database or the clock —
//! the caller passes the present in.

use chrono::{DateTime, Utc};

use super::super::errors::JourneyError;

/// 2025-01-01T00:00:00Z, as an epoch second. No session predates the first
/// build of the app, and a row dated earlier is a broken clock rather than a
/// memory. Rejected rather than clamped: a silently moved date would land in
/// somebody's streak. A timestamp rather than a string, so the check is a
/// comparison rather than a parse repeated for every record of a batch.
const EARLIEST_SESSION_TIMESTAMP: i64 = 1_735_689_600;

/// How far ahead of the server's clock a session may claim to have started.
///
/// Generous enough to absorb a device whose clock is a few hours out, tight
/// enough that a session dated next year cannot hold a streak open forever.
const MAX_CLOCK_SKEW_HOURS: i64 = 24;

/// Refuses a start time that cannot be a real session.
///
/// Both bounds guard streaks rather than storage: a session dated 1970 would sit
/// harmlessly in the table, but a session dated next year holds a current streak
/// open indefinitely and nothing later can close it.
pub(super) fn validate_started_at(
    started_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> Result<(), JourneyError> {
    if started_at.timestamp() < EARLIEST_SESSION_TIMESTAMP {
        return Err(JourneyError::Invalid(
            "`started_at` predates the app".to_owned(),
        ));
    }

    if started_at > now + chrono::Duration::hours(MAX_CLOCK_SKEW_HOURS) {
        return Err(JourneyError::Invalid(
            "`started_at` is in the future".to_owned(),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A future-dated session would hold a current streak open forever, and
    /// nothing recorded later could close it. Real clock skew is absorbed;
    /// a date next year is not.
    #[test]
    fn a_future_session_is_refused_but_clock_skew_is_not() {
        let now = DateTime::from_timestamp(1_777_000_000, 0).expect("a representable instant");

        assert!(validate_started_at(now + chrono::Duration::hours(1), now).is_ok());
        assert!(matches!(
            validate_started_at(now + chrono::Duration::days(30), now),
            Err(JourneyError::Invalid(_))
        ));
        assert!(matches!(
            validate_started_at(
                DateTime::from_timestamp(0, 0).expect("the epoch is representable"),
                now
            ),
            Err(JourneyError::Invalid(_))
        ));
    }
}
