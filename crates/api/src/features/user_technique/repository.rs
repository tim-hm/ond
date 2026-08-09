//! User technique SQL.

use sqlx::{PgPool, Postgres, Transaction};
use tokio::sync::OnceCell;
use uuid::Uuid;

use super::errors::UserTechniqueError;
use super::types::{AuthoredTechnique, PhaseLimit, PhaseLimits};
use crate::features::technique::types::{Passage, PhaseKind, TechniqueGoal};
use crate::identity::UserId;

/// One authored technique without its stages.
pub struct UserTechniqueRow {
    pub id: Uuid,
    pub name: String,
    /// Empty where the author wrote none — the column defaults to it rather
    /// than to null.
    pub summary: String,
    pub goal: TechniqueGoal,
    pub rounds: i32,
}

/// One stage, carrying the id of the technique it belongs to so the caller can
/// group without a second lookup — the same shape the catalogue's read path uses.
pub struct StageRow {
    pub technique_id: Uuid,
    pub ordinal: i32,
    pub cycles: i32,
}

pub struct PhaseRow {
    pub technique_id: Uuid,
    pub stage_ordinal: i32,
    pub kind: PhaseKind,
    /// `None` exactly when `kind` is a hold, held by the column's `CHECK`.
    pub passage: Option<Passage>,
    pub duration_ms: i32,
}

/// The safe range each phase kind may be authored within, derived from the
/// seeded catalogue.
///
/// The whole of clause "the seeded safe per-phase ranges still bound it": the
/// widest interval the curated techniques put a phase of this kind in. Deriving
/// rather than seeding a second table means widening a technique's range widens
/// what can be composed, with no second number to keep in step — and it means
/// this limit cannot be edited without editing the evidence it came from.
///
/// Open-ended stages are excluded. A sixty-second retention is safe because the
/// person ends it the moment they need to, which is not a property a scheduled
/// hold inherits; including it would let somebody author a minute-long
/// breath-hold on a clock.
///
/// `ORDER BY kind` is the enum's declaration order, which is inhale, hold in,
/// exhale, hold out — the order a cycle runs in, and therefore the order a
/// client wants to render a picker in.
pub async fn phase_limits(pool: &PgPool) -> Result<PhaseLimits, UserTechniqueError> {
    let rows = sqlx::query!(
        r#"SELECT
            p.kind AS "kind: PhaseKind",
            MIN(p.min_duration_ms) AS "min_duration_ms!",
            MAX(p.max_duration_ms) AS "max_duration_ms!"
         FROM technique_phases p
         JOIN technique_stages s
           ON s.technique_id = p.technique_id AND s.ordinal = p.stage_ordinal
         WHERE NOT s.open_ended
         GROUP BY p.kind
         ORDER BY p.kind"#
    )
    .fetch_all(pool)
    .await?;

    Ok(PhaseLimits::new(
        rows.into_iter()
            .map(|row| PhaseLimit {
                kind: row.kind,
                min_duration_ms: row.min_duration_ms,
                max_duration_ms: row.max_duration_ms,
            })
            .collect(),
    ))
}

/// [`phase_limits`], derived once per process and then read from memory.
///
/// The ranges derive purely from the seeded catalogue, and the catalogue
/// changes only when a deploy re-runs the migrations — which restarts this
/// process and so re-derives. Caching here keeps the "derived, not seeded
/// twice" property while taking the `JOIN`/`GROUP BY` off every list, create
/// and update. One cache per transport instance rather than a process global,
/// so each e2e stack derives from its own database.
pub struct PhaseLimitsCache(OnceCell<PhaseLimits>);

impl PhaseLimitsCache {
    pub const fn new() -> Self {
        Self(OnceCell::const_new())
    }

    /// The cached limits, deriving them on the first call.
    ///
    /// An empty derivation is refused rather than cached. The one way it
    /// happens is a request landing between `dev:db:reset`'s schema and seed
    /// steps, and caching that answer would refuse every create until the
    /// process restarts; erroring instead leaves the cell empty, so the next
    /// request re-derives and the cache stays self-healing.
    pub async fn get(&self, pool: &PgPool) -> Result<&PhaseLimits, UserTechniqueError> {
        self.0
            .get_or_try_init(|| async {
                let limits = phase_limits(pool).await?;
                if limits.iter().next().is_none() {
                    return Err(UserTechniqueError::Inconsistent(
                        "the catalogue has no phase limits to derive".to_owned(),
                    ));
                }
                Ok(limits)
            })
            .await
    }
}

/// This person's techniques, oldest first.
///
/// Tie-broken on `id` so two techniques created in the same clock tick keep a
/// stable order between calls — a list that reshuffles under a person is a bug
/// they would report as their techniques having moved.
pub async fn list_techniques(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Vec<UserTechniqueRow>, UserTechniqueError> {
    let rows = sqlx::query_as!(
        UserTechniqueRow,
        r#"SELECT id, name, summary, goal AS "goal: TechniqueGoal", rounds
           FROM user_techniques
           WHERE user_id = $1
           ORDER BY created_at, id"#,
        user_id.0
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Every stage of every technique this person owns, in play order.
///
/// One query for the whole list rather than one per technique, for the reason
/// the catalogue does the same: the list is capped at
/// [`super::types::MAX_TECHNIQUES`], so the per-technique variant would be a
/// textbook N+1 with a known ceiling and no benefit.
pub async fn list_stages(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Vec<StageRow>, UserTechniqueError> {
    let rows = sqlx::query_as!(
        StageRow,
        r"SELECT s.technique_id, s.ordinal, s.cycles
          FROM user_technique_stages s
          JOIN user_techniques t ON t.id = s.technique_id
          WHERE t.user_id = $1
          ORDER BY s.technique_id, s.ordinal",
        user_id.0
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Every phase of every technique this person owns, in cycle order.
pub async fn list_phases(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Vec<PhaseRow>, UserTechniqueError> {
    let rows = sqlx::query_as!(
        PhaseRow,
        r#"SELECT
            p.technique_id,
            p.stage_ordinal,
            p.kind AS "kind: PhaseKind",
            p.passage AS "passage: Passage",
            p.duration_ms
         FROM user_technique_phases p
         JOIN user_techniques t ON t.id = p.technique_id
         WHERE t.user_id = $1
         ORDER BY p.technique_id, p.stage_ordinal, p.ordinal"#,
        user_id.0
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Stores a new technique and returns the id it was minted with, or `None` for
/// a caller already holding `cap`.
///
/// One transaction across all three tables: a technique whose stages were
/// committed and whose phases were not is a row the read path refuses to serve
/// at all, so a partial write would cost the person their whole list rather than
/// one technique.
///
/// The cap is counted inside that transaction, behind `FOR UPDATE` on the
/// caller's `users` row — the same per-person lock account merge and deletion
/// take — because a count taken outside it races: two creates at nineteen
/// both read nineteen and both inserted. The lock releases on commit and
/// error alike, so the blocked create's count then sees the committed row and
/// refuses. An absent row is not an error here: `identity::resolve` upserted
/// it before any handler ran, so absence means the account is being deleted
/// mid-request, and the insert's foreign key answers that exactly as it did
/// before this lock existed.
pub async fn insert_bounded(
    pool: &PgPool,
    user_id: UserId,
    authored: &AuthoredTechnique,
    cap: i64,
) -> Result<Option<Uuid>, UserTechniqueError> {
    let mut tx = pool.begin().await?;

    sqlx::query_scalar!("SELECT id FROM users WHERE id = $1 FOR UPDATE", user_id.0)
        .fetch_optional(&mut *tx)
        .await?;

    let held = sqlx::query_scalar!(
        r#"SELECT count(*) AS "count!" FROM user_techniques WHERE user_id = $1"#,
        user_id.0
    )
    .fetch_one(&mut *tx)
    .await?;

    if held >= cap {
        return Ok(None);
    }

    let id = sqlx::query_scalar!(
        "INSERT INTO user_techniques (user_id, name, summary, goal, rounds)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id",
        user_id.0,
        authored.name,
        authored.summary,
        authored.goal as _,
        authored.rounds
    )
    .fetch_one(&mut *tx)
    .await?;

    insert_stages(&mut tx, id, authored).await?;
    tx.commit().await?;

    Ok(Some(id))
}

/// Replaces a technique's whole content, or reports that it is not this
/// caller's.
///
/// The stage and phase rows are deleted and rewritten rather than diffed. An
/// edit that removes a phase from the middle renumbers every phase after it, so
/// a diff would be a rewrite with extra steps — and this way the ordinals are
/// dense by construction on every write path, not just the first.
pub async fn replace(
    pool: &PgPool,
    user_id: UserId,
    id: Uuid,
    authored: &AuthoredTechnique,
) -> Result<(), UserTechniqueError> {
    let mut tx = pool.begin().await?;

    // `user_id` in the predicate rather than a separate ownership read: one
    // statement cannot race an interleaved delete, and two would need the same
    // transaction to be worth writing.
    let updated = sqlx::query_scalar!(
        "UPDATE user_techniques
         SET name = $3, summary = $4, goal = $5, rounds = $6, updated_at = now()
         WHERE id = $1 AND user_id = $2
         RETURNING id",
        id,
        user_id.0,
        authored.name,
        authored.summary,
        authored.goal as _,
        authored.rounds
    )
    .fetch_optional(&mut *tx)
    .await?;

    if updated.is_none() {
        return Err(UserTechniqueError::NotFound);
    }

    // The phases go with them, by cascade.
    sqlx::query!(
        "DELETE FROM user_technique_stages WHERE technique_id = $1",
        id
    )
    .execute(&mut *tx)
    .await?;

    insert_stages(&mut tx, id, authored).await?;
    tx.commit().await?;

    Ok(())
}

/// Deletes a technique, saying nothing about whether it was there.
///
/// Idempotent on purpose: a client retrying a delete it never saw the answer to
/// should converge rather than raise an error about a technique the person can
/// no longer see.
pub async fn delete(pool: &PgPool, user_id: UserId, id: Uuid) -> Result<(), UserTechniqueError> {
    sqlx::query!(
        "DELETE FROM user_techniques WHERE id = $1 AND user_id = $2",
        id,
        user_id.0
    )
    .execute(pool)
    .await?;

    Ok(())
}

/// Writes the stage and phase rows for a technique whose parent row already
/// exists in `tx`.
///
/// Two statements over unnested arrays rather than a loop, so the whole
/// structure lands in two round trips whatever its shape. Ordinals are the
/// positions in the validated draft, which is what makes them dense and what
/// makes the phases' composite foreign key resolve.
async fn insert_stages(
    tx: &mut Transaction<'_, Postgres>,
    id: Uuid,
    authored: &AuthoredTechnique,
) -> Result<(), UserTechniqueError> {
    let stage_ordinals: Vec<i32> = (0i32..).take(authored.stages.len()).collect();
    let cycles: Vec<i32> = authored.stages.iter().map(|stage| stage.cycles).collect();

    sqlx::query!(
        "INSERT INTO user_technique_stages (technique_id, ordinal, cycles)
         SELECT $1, s.ordinal, s.cycles
         FROM UNNEST($2::integer[], $3::integer[]) AS s(ordinal, cycles)",
        id,
        &stage_ordinals,
        &cycles
    )
    .execute(&mut **tx)
    .await?;

    let mut phase_stages: Vec<i32> = Vec::new();
    let mut phase_ordinals: Vec<i32> = Vec::new();
    let mut kinds: Vec<PhaseKind> = Vec::new();
    let mut passages: Vec<Option<Passage>> = Vec::new();
    let mut durations: Vec<i32> = Vec::new();
    // Counted in `i32` rather than `usize` because that is the column's width;
    // the validated draft is far too short for the ranges to run out.
    for (stage_ordinal, stage) in (0i32..).zip(&authored.stages) {
        for (ordinal, phase) in (0i32..).zip(&stage.phases) {
            phase_stages.push(stage_ordinal);
            phase_ordinals.push(ordinal);
            kinds.push(phase.kind);
            passages.push(phase.passage);
            durations.push(phase.duration_ms);
        }
    }

    sqlx::query!(
        "INSERT INTO user_technique_phases
            (technique_id, stage_ordinal, ordinal, kind, passage, duration_ms)
         SELECT $1, p.stage_ordinal, p.ordinal, p.kind, p.passage, p.duration_ms
         FROM UNNEST($2::integer[], $3::integer[], $4::phase_kind[], $5::passage[],
                     $6::integer[])
              AS p(stage_ordinal, ordinal, kind, passage, duration_ms)",
        id,
        &phase_stages,
        &phase_ordinals,
        &kinds as _,
        &passages as _,
        &durations
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}
