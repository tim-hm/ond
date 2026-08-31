//! Both directions across the proto boundary for one session record.
//!
//! The inbound direction validates as it converts, so no caller can build a
//! `SessionRow` this module has not checked.

use chrono::Utc;

use super::super::errors::JourneyError;
use super::super::wire::timestamp_from_proto;
use super::repository::SessionRow;
use super::validation::validate_started_at;
use crate::features::technique::convert::surface_to_proto;
use crate::features::technique::types::{DeliverySurface, OccasionSlug, TechniqueSlug};
use crate::proto::ond::v1 as pb;
use crate::wire::{self, counted, timestamp_to_proto};

/// Twelve hours. Longer than any session the app can produce and short enough
/// that a stuck timer arrives as a rejection rather than as a person's totals.
const MAX_SESSION_DURATION_MS: u32 = 12 * 60 * 60 * 1000;

const MAX_CYCLES_PER_SESSION: u32 = 10_000;
const MAX_BREATHS_PER_SESSION: u32 = 100_000;

/// Narrows one submitted session to something the database accepts. Every
/// rejection is a value the wire format admits and no session can produce. The
/// whole batch fails rather than dropping the offending record: recording the
/// other ninety-nine would hide the client bug and leave an untraceable gap.
pub(super) fn session_from_proto(record: &pb::SessionRecord) -> Result<SessionRow, JourneyError> {
    let client_session_id = wire::uuid("client_session_id", &record.client_session_id)?;
    let technique_slug = TechniqueSlug::parse("technique_slug", &record.technique_slug)?;

    let started_at = record
        .started_at
        .as_ref()
        .ok_or_else(|| JourneyError::Invalid("`started_at` is required".to_owned()))
        .and_then(|stamp| timestamp_from_proto(stamp, "started_at"))?;
    validate_started_at(started_at, Utc::now())?;

    // Absent is the ordinary case — a person picking a technique themselves —
    // but a client that *set* an empty or oversized slug has a bug, and the
    // batch fails on it like any other impossible value.
    let occasion_slug = record
        .occasion_slug
        .as_deref()
        .map(|raw| OccasionSlug::parse("occasion_slug", raw))
        .transpose()?;

    // Unspecified is a record from before the field existed and stores as
    // null; a value outside the enum is a client this server does not know.
    let surface = match pb::DeliverySurface::try_from(record.surface) {
        Ok(pb::DeliverySurface::Unspecified) => None,
        Ok(pb::DeliverySurface::FullScreen) => Some(DeliverySurface::FullScreen),
        Ok(pb::DeliverySurface::Discreet) => Some(DeliverySurface::Discreet),
        Err(_) => {
            return Err(JourneyError::Invalid(format!(
                "`surface` `{}` is not one we know",
                record.surface
            )));
        }
    };

    Ok(SessionRow {
        client_session_id,
        technique_slug,
        started_at,
        duration_ms: bounded(record.duration_ms, MAX_SESSION_DURATION_MS, "duration_ms")?,
        cycles_completed: bounded(
            record.cycles_completed,
            MAX_CYCLES_PER_SESSION,
            "cycles_completed",
        )?,
        breath_count: bounded(record.breath_count, MAX_BREATHS_PER_SESSION, "breath_count")?,
        completed: record.completed,
        occasion_slug,
        surface,
    })
}

pub(super) fn session_to_proto(row: SessionRow) -> Result<pb::SessionRecord, JourneyError> {
    Ok(pb::SessionRecord {
        client_session_id: row.client_session_id.to_string(),
        technique_slug: row.technique_slug.into_string(),
        started_at: Some(timestamp_to_proto(row.started_at)),
        duration_ms: counted("duration_ms", row.duration_ms)?,
        cycles_completed: counted("cycles_completed", row.cycles_completed)?,
        breath_count: counted("breath_count", row.breath_count)?,
        completed: row.completed,
        occasion_slug: row.occasion_slug.map(OccasionSlug::into_string),
        surface: row
            .surface
            .map_or(pb::DeliverySurface::Unspecified, surface_to_proto) as i32,
    })
}

fn bounded(value: u32, maximum: u32, field: &str) -> Result<i32, JourneyError> {
    if value > maximum {
        return Err(JourneyError::Invalid(format!(
            "`{field}` is larger than {maximum}"
        )));
    }

    i32::try_from(value).map_err(|_| JourneyError::Invalid(format!("`{field}` is out of range")))
}

#[cfg(test)]
mod tests {
    use chrono::DateTime;
    use uuid::Uuid;

    use super::*;

    fn record(started_at: DateTime<Utc>) -> pb::SessionRecord {
        pb::SessionRecord {
            client_session_id: Uuid::nil().to_string(),
            technique_slug: "box-breathing".to_owned(),
            started_at: Some(timestamp_to_proto(started_at)),
            duration_ms: 60_000,
            cycles_completed: 4,
            breath_count: 8,
            completed: true,
            occasion_slug: None,
            surface: pb::DeliverySurface::Unspecified as i32,
        }
    }

    /// A session the app cannot have produced fails the batch rather than being
    /// stored — an hour-long "cycle count" of four billion would otherwise sit
    /// in somebody's totals forever.
    #[test]
    fn an_impossible_session_fails_the_batch() {
        let now = Utc::now();

        let mut too_long = record(now);
        too_long.duration_ms = MAX_SESSION_DURATION_MS + 1;
        assert!(matches!(
            session_from_proto(&too_long),
            Err(JourneyError::Invalid(_))
        ));

        let mut no_slug = record(now);
        no_slug.technique_slug = "   ".to_owned();
        assert!(matches!(
            session_from_proto(&no_slug),
            Err(JourneyError::Invalid(_))
        ));

        let mut bad_id = record(now);
        bad_id.client_session_id = "not-a-uuid".to_owned();
        assert!(matches!(
            session_from_proto(&bad_id),
            Err(JourneyError::Invalid(_))
        ));

        // Absent is the ordinary case; *set* to blank is a client bug.
        let mut blank_occasion = record(now);
        blank_occasion.occasion_slug = Some("   ".to_owned());
        assert!(matches!(
            session_from_proto(&blank_occasion),
            Err(JourneyError::Invalid(_))
        ));

        let mut alien_surface = record(now);
        alien_surface.surface = 99;
        assert!(matches!(
            session_from_proto(&alien_surface),
            Err(JourneyError::Invalid(_))
        ));

        assert!(session_from_proto(&record(now)).is_ok());
    }
}
