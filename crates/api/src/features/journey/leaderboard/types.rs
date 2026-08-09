//! Domain enums for the leaderboards.
//!
//! Both exist to keep the proto zero values from reaching the repository as a
//! third "no board asked for" case. Only one of them is also a Postgres type: a
//! board names a snapshot key, whereas a scope is still a choice made at read
//! time and never stored.

/// Which measure a board ranks people by.
///
/// Mirrors the `leaderboard_board` Postgres enum. Every variant is renamed
/// explicitly rather than through `rename_all`, for the reason `BirthYearBand`
/// is: a label containing digits has no case convention anybody should have to
/// guess at.
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
    /// Every other board is a bigger-is-better measure, and this one is not: a
    /// resting breath that has slowed is the direction practice moves it. Kept
    /// as a multiplier rather than a branch in the ranked read, so there is one
    /// statement for every board and `sqlx::query!` goes on checking it against
    /// the real schema at compile time.
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
