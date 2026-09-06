//! Domain enums, mirroring the Postgres types declared in
//! `0004_users_and_profiles.sql`, and the one shape another feature reads.
//!
//! No enum here carries an "unspecified" variant: a value that reaches the
//! repository is one the database accepts. A meaningful zero value is `Option`.

/// Mirrors the `experience_level` Postgres enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "experience_level", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ExperienceLevel {
    New,
    Occasional,
    Regular,
}

/// How long a display name may be, in characters.
///
/// One constant for the whole feature: validation rejects an over-long name
/// with it, and the collision suffix trims against it. Two that disagreed would
/// build a candidate the `CHECK` in `0005_journey.sql` refuses as `internal`.
pub const MAX_DISPLAY_NAME_CHARS: usize = 24;

/// How long a given name may be, in characters — matching the `CHECK` on
/// `users.given_name`.
///
/// Its own constant, not a reuse of the display name's: the two are bounded for
/// different reasons, so one constant would make moving either move both.
pub const MAX_GIVEN_NAME_CHARS: usize = 24;

/// Mirrors the `birth_year_band` Postgres enum.
///
/// Each variant is renamed explicitly: the labels contain digits, which no case
/// convention maps predictably. `Born2000s` is the youngest band on purpose —
/// `profile_service.proto` names what adding a younger one would also move.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "birth_year_band")]
pub enum BirthYearBand {
    #[sqlx(rename = "BORN_BEFORE_1960")]
    BornBefore1960,
    #[sqlx(rename = "BORN_1960S")]
    Born1960s,
    #[sqlx(rename = "BORN_1970S")]
    Born1970s,
    #[sqlx(rename = "BORN_1980S")]
    Born1980s,
    #[sqlx(rename = "BORN_1990S")]
    Born1990s,
    #[sqlx(rename = "BORN_2000S")]
    Born2000s,
}

/// Mirrors the `gender` Postgres enum.
///
/// "Rather not say" is `Option::None` end to end, never a variant; the case
/// for the closed list lives on the contract, in `profile_service.proto`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "gender", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Gender {
    Female,
    Male,
    NonBinary,
}

/// Mirrors the `reminder_intensity` Postgres enum.
///
/// `Never` is the default in every direction — the column default, the proto
/// zero value, and the variant a decode falls back to — so nothing that goes
/// wrong along the way can turn silence into a notification.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, sqlx::Type)]
#[sqlx(type_name = "reminder_intensity", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ReminderIntensity {
    #[default]
    Never,
    Gentle,
    Daily,
}
