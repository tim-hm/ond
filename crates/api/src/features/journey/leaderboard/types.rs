//! Domain enums for the leaderboards.
//!
//! Both keep the proto zero values from reaching the repository as a third "no
//! board asked for" case. Only `LeaderboardBoard` is also a Postgres type: it
//! names a snapshot key, whereas a scope is chosen at read time and never stored.

/// Which measure a board ranks people by.
///
/// Mirrors the `leaderboard_board` Postgres enum. Variants are renamed
/// explicitly rather than through `rename_all`, as `BirthYearBand` is: a label
/// containing digits has no case convention to guess at.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "leaderboard_board")]
pub enum LeaderboardBoard {
    /// Consecutive local days ending today or yesterday.
    #[sqlx(rename = "STREAK")]
    Streak,
    /// Minutes breathed in the last thirty days.
    #[sqlx(rename = "MINUTES_30D")]
    Minutes30d,
    /// Best BOLT-style controlled pause, in seconds.
    #[sqlx(rename = "BOLT")]
    Bolt,
    /// Lowest resting breathing rate, in breaths a minute.
    #[sqlx(rename = "RESTING_RATE")]
    RestingRate,
}

impl LeaderboardBoard {
    /// Which way "better" points on this board.
    ///
    /// Resting rate is the one board where lower is better. A multiplier rather
    /// than a branch in the ranked read, so one statement serves every board and
    /// `sqlx::query!` still checks it against the schema at compile time.
    pub const fn ranking_sign(self) -> i32 {
        match self {
            Self::Streak | Self::Minutes30d | Self::Bolt => 1,
            Self::RestingRate => -1,
        }
    }
}

/// Who a board is drawn from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LeaderboardScope {
    Global,
    /// Only people sharing the caller's birth-year band.
    AgeBand,
}
