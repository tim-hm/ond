//! Domain enums, mirroring the Postgres types declared in `0001_init.sql`.
//!
//! They are distinct from the generated proto enums on purpose: a proto enum carries an
//! `_UNSPECIFIED` zero the wire format can always produce, and these carry no such variant, so a
//! value that reaches the repository is already one the database accepts.

use std::fmt;

use crate::wire::Malformed;

#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, serde::Deserialize)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "snake_case")]
pub enum TechniqueGoal {
    Calm,
    Sleep,
    Energy,
    Reset,
    Focus,
}

/// Mirrors the `phase_kind` Postgres enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "phase_kind", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PhaseKind {
    Inhale,
    HoldIn,
    Exhale,
    HoldOut,
}

impl PhaseKind {
    /// Whether the breath is moving rather than being held — which is exactly
    /// when a phase has a passage, on the wire and in the column's `CHECK`.
    pub const fn is_breathing(self) -> bool {
        matches!(self, Self::Inhale | Self::Exhale)
    }
}

/// Mirrors the `delivery_surface` Postgres enum — how loudly the session an
/// occasion prescribes runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "delivery_surface", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DeliverySurface {
    FullScreen,
    Discreet,
}

/// Mirrors the `copy_register` Postgres enum — which words the session an
/// occasion prescribes speaks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "copy_register", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CopyRegister {
    Plain,
    Playful,
}

/// Mirrors the `evidence_grade` Postgres enum — how well research supports an exercise.
///
/// Optional wherever it is carried: ungraded is an answer rather than a missing value, and it
/// belongs to the exercises people write themselves, which reach the wire through
/// `user_technique`. There is deliberately no `Strong` — see the note on the proto enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "evidence_grade", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EvidenceGrade {
    Moderate,
    Limited,
}

/// How the items after a reading lead are presented.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ReadingListStyle {
    None,
    Bullets,
    Numbered,
}

/// A short lead followed, where useful, by a scannable list.
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingContent {
    pub lead: String,
    pub items: Vec<String>,
    pub list_style: ReadingListStyle,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, serde::Deserialize)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "snake_case")]
pub enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "manner", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Manner {
    CurledTongue,
    PursedLips,
    Hum,
}

/// One stage of a technique as another feature reads it.
pub struct PlayableStage {
    /// How many times the phases repeat, always positive.
    pub cycles: i32,

    /// An open-ended stage runs until the person ends it; its `cycles` value is
    /// presentational and an offer never overrides it.
    pub open_ended: bool,

    /// In cycle order, never empty.
    pub phases: Vec<PlayablePhase>,
}

/// One phase of a stage, carrying its curated duration and the safe range the
/// dial — and any exercise offer — must stay inside.
pub struct PlayablePhase {
    pub kind: PhaseKind,

    pub passage: Option<Passage>,

    pub manner: Option<Manner>,

    pub duration_ms: i32,
    pub min_duration_ms: i32,
    pub max_duration_ms: i32,

    pub turn_gap_ms: Option<i32>,
    pub haptic_pattern: Option<String>,
}

/// The longest slug the wire accepts, in characters — matching the `CHECK` on
/// `sessions.technique_slug`. Applied in one place, [`TechniqueSlug::parse`],
/// so the bound cannot drift per feature the way it did while each feature
/// that read a client-supplied slug checked it itself.
pub const MAX_SLUG_CHARS: usize = 64;

/// A catalogue technique's stable key: what a client navigates by and what a
/// `sessions` row records. A type rather than a `String` because a technique
/// carries this and a [`TechniqueId`] side by side, which to a compiler are
/// one thing. It arrives from a column the `CHECK` has bounded, or through
/// [`TechniqueSlug::parse`].
#[derive(Debug, Clone, PartialEq, Eq, Hash, sqlx::Type)]
#[sqlx(transparent)]
pub struct TechniqueSlug(String);

/// An occasion's own stable key, in the namespace beside the technique slug it
/// prescribes — `occasions.slug` and `occasions.technique_slug` are different
/// columns, and a row carries one of each.
#[derive(Debug, Clone, PartialEq, Eq, Hash, sqlx::Type)]
#[sqlx(transparent)]
pub struct OccasionSlug(String);

/// A technique row's surrogate key, which the seed mints as a cuid2.
///
/// Nothing checks its shape: what it looks like is the seed's business. It is a
/// type only so that it cannot be handed to something expecting the slug — the
/// mistake that compiles and surfaces as a `NOT_FOUND` a client cannot explain.
#[derive(Debug, Clone, PartialEq, Eq, Hash, sqlx::Type)]
#[sqlx(transparent)]
pub struct TechniqueId(String);

impl TechniqueSlug {
    /// Narrows one of a client's strings, naming the field it arrived in.
    pub fn parse(field: &str, raw: &str) -> Result<Self, Malformed> {
        bounded(field, raw).map(Self)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Gives the string back on the way out to the wire, where proto3 has no
    /// type to carry the distinction this one exists for.
    pub fn into_string(self) -> String {
        self.0
    }
}

impl OccasionSlug {
    /// [`TechniqueSlug::parse`]'s bound, applied to the other namespace.
    pub fn parse(field: &str, raw: &str) -> Result<Self, Malformed> {
        bounded(field, raw).map(Self)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// [`TechniqueSlug::into_string`]'s exit, for the other namespace.
    pub fn into_string(self) -> String {
        self.0
    }
}

impl TechniqueId {
    /// [`TechniqueSlug::into_string`]'s exit, for the surrogate key.
    pub fn into_string(self) -> String {
        self.0
    }
}

#[cfg(test)]
impl TechniqueId {
    /// Fixture-only. Every shipping path reads one out of a column, so nothing
    /// outside a test has any business minting a surrogate key.
    pub fn test(id: &str) -> Self {
        Self(id.to_owned())
    }
}

/// The one place the slug bound is applied. Trimmed first: a slug arriving with
/// surrounding space is a client bug, and storing it would record a session
/// against a technique nothing can ever match.
fn bounded(field: &str, raw: &str) -> Result<String, Malformed> {
    let slug = raw.trim();
    if slug.is_empty() || slug.chars().count() > MAX_SLUG_CHARS {
        return Err(Malformed(format!(
            "`{field}` must be between 1 and {MAX_SLUG_CHARS} characters"
        )));
    }
    Ok(slug.to_owned())
}

impl fmt::Display for TechniqueSlug {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl fmt::Display for OccasionSlug {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl fmt::Display for TechniqueId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The bound is the `CHECK`'s, and it is inclusive at the top: a slug of
    /// exactly the limit is one the column accepts, and refusing it here would
    /// make the documented number wrong by one.
    #[test]
    fn the_slug_bound_matches_the_column() {
        let longest = "a".repeat(MAX_SLUG_CHARS);
        assert_eq!(
            TechniqueSlug::parse("technique_slug", &longest)
                .expect("the limit itself is a slug")
                .as_str(),
            longest
        );

        assert!(TechniqueSlug::parse("technique_slug", &"a".repeat(MAX_SLUG_CHARS + 1)).is_err());
        assert!(TechniqueSlug::parse("technique_slug", "").is_err());
        assert!(TechniqueSlug::parse("technique_slug", "   ").is_err());
    }

    /// Surrounding space is trimmed rather than refused, so a client that pads
    /// a slug records the session it meant instead of one nothing matches.
    #[test]
    fn a_padded_slug_is_the_slug_it_names() {
        assert_eq!(
            TechniqueSlug::parse("technique_slug", "  box-breathing\n")
                .expect("padding is not a rejection")
                .as_str(),
            "box-breathing"
        );
    }
}
