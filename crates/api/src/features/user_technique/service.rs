//! Business logic — the four things a person can do to their own exercises.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`. Checking a draft
//! is `super::validation`; assembling a response is `super::convert`.

use sqlx::PgPool;

use super::convert::{
    StoredTechnique, assemble_stages, authored_to_proto, limits_to_proto, technique_to_proto,
};
use super::errors::UserTechniqueError;
use super::repository;
use super::types::{MAX_TECHNIQUES, PhaseLimits, SavedSummary};
use super::validation::validate;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;
use crate::wire;

/// Whether this draft is one this feature would accept, for another feature
/// about to propose it. The assistant's save-this-pattern card runs the same
/// validator, so the server never offers to save what [`create`] then refuses.
/// It lives here because `super::validation` is private. The validated value is
/// discarded; the caller wants the verdict, not the draft.
pub fn validate_draft(
    draft: pb::TechniqueDraft,
    limits: &PhaseLimits,
) -> Result<(), UserTechniqueError> {
    validate(Some(draft), limits).map(|_| ())
}

/// What this person has named their own exercises, for the coach that offers
/// to make more of them. Without it the assistant offered to save patterns
/// somebody already owned, and could not answer "the one I made for the
/// evenings". One query, no stages, no limits. Deliberately not [`list`], which
/// returns the wire shape and fires two more queries to assemble every phase.
pub async fn saved_summaries(
    pool: &PgPool,
    user_id: UserId,
) -> Result<Vec<SavedSummary>, UserTechniqueError> {
    // This rides in the per-caller half of the prompt, which is billed in full
    // on every question, so it projects down to the two fields a sentence can
    // use. The read is shared rather than duplicated: a near-duplicate `SELECT`
    // of three columns buys nothing at `MAX_TECHNIQUES` rows, and that cap is
    // also why nothing here needs a limit of its own.
    let rows = repository::list_techniques(pool, user_id).await?;

    Ok(rows
        .into_iter()
        .map(|row| SavedSummary {
            name: row.name,
            goal: row.goal,
        })
        .collect())
}

/// This person's techniques, and the limits a composer has to work inside.
///
/// `limits` arrives from the handler's [`super::cache::PhaseLimitsCache`] rather
/// than being read here, so the derivation is paid once per process instead of
/// once per RPC.
pub async fn list(
    pool: &PgPool,
    user_id: UserId,
    limits: &PhaseLimits,
) -> Result<pb::ListUserTechniquesResponse, UserTechniqueError> {
    // Concurrently: three independent reads on the composer's screen-open
    // path, where serial awaits summed their latencies for no ordering gain.
    let (techniques, stages, phases) = tokio::try_join!(
        repository::list_techniques(pool, user_id),
        repository::list_stages(pool, user_id),
        repository::list_phases(pool, user_id),
    )?;

    let mut stages_by_technique = assemble_stages(stages, phases, limits)?;

    let techniques = techniques
        .into_iter()
        .map(|row| {
            let stages = stages_by_technique.remove(&row.id).ok_or_else(|| {
                UserTechniqueError::Inconsistent(format!("technique `{}` has no stages", row.id))
            })?;

            technique_to_proto(
                StoredTechnique {
                    id: row.id,
                    name: &row.name,
                    summary: &row.summary,
                    goal: row.goal,
                    rounds: row.rounds,
                },
                stages,
            )
        })
        .collect::<Result<Vec<_>, UserTechniqueError>>()?;

    Ok(pb::ListUserTechniquesResponse {
        techniques,
        limits: Some(limits_to_proto(limits)?),
    })
}

/// Stores a draft and returns it as the catalogue would describe it.
pub async fn create(
    pool: &PgPool,
    user_id: UserId,
    draft: Option<pb::TechniqueDraft>,
    limits: &PhaseLimits,
) -> Result<pb::CreateUserTechniqueResponse, UserTechniqueError> {
    let authored = validate(draft, limits)?;

    // Counted rather than enforced by a constraint: "you have twenty already"
    // is a sentence a person can act on, where a unique-violation turned into
    // `internal` is one nobody can. The counting itself lives inside the
    // insert's transaction — see `insert_bounded` for the race it closes.
    let Some(id) =
        repository::insert_bounded(pool, user_id, &authored, i64::from(MAX_TECHNIQUES)).await?
    else {
        return Err(UserTechniqueError::TooMany(format!(
            "you can keep {MAX_TECHNIQUES} of your own exercises — delete one to make room"
        )));
    };

    Ok(pb::CreateUserTechniqueResponse {
        technique: Some(authored_to_proto(id, &authored, limits)?),
    })
}

/// Replaces a technique this person owns.
///
/// Re-validated against the limits as they are now, not as they were when it was
/// first stored: an edit is a new claim about what is safe to breathe, and it is
/// checked as one.
pub async fn update(
    pool: &PgPool,
    user_id: UserId,
    id: &str,
    draft: Option<pb::TechniqueDraft>,
    limits: &PhaseLimits,
) -> Result<pb::UpdateUserTechniqueResponse, UserTechniqueError> {
    let id = wire::uuid("id", id)?;
    let authored = validate(draft, limits)?;

    repository::replace(pool, user_id, id, &authored).await?;

    Ok(pb::UpdateUserTechniqueResponse {
        technique: Some(authored_to_proto(id, &authored, limits)?),
    })
}

/// Deletes a technique this person owns, or one they never had.
pub async fn delete(
    pool: &PgPool,
    user_id: UserId,
    id: &str,
) -> Result<pb::DeleteUserTechniqueResponse, UserTechniqueError> {
    let id = wire::uuid("id", id)?;
    repository::delete(pool, user_id, id).await?;

    Ok(pb::DeleteUserTechniqueResponse {})
}
