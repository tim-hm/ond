//! Business logic — the four things a person can do to their own exercises.
//!
//! Receives explicit dependencies (`&PgPool`), never `Arc<AppState>`, and
//! contains zero raw queries: SQL lives in `super::repository`. Checking a draft
//! is `super::validation`; assembling a response is `super::convert`.

use sqlx::PgPool;
use uuid::Uuid;

use super::convert::{
    StoredTechnique, assemble_stages, authored_to_proto, limits_to_proto, technique_to_proto,
};
use super::errors::UserTechniqueError;
use super::repository;
use super::types::MAX_TECHNIQUES;
use super::validation::validate;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// This person's techniques, and the limits a composer has to work inside.
pub async fn list(
    pool: &PgPool,
    user_id: UserId,
) -> Result<pb::ListUserTechniquesResponse, UserTechniqueError> {
    let limits = repository::phase_limits(pool).await?;
    let techniques = repository::list_techniques(pool, user_id).await?;
    let stages = repository::list_stages(pool, user_id).await?;
    let phases = repository::list_phases(pool, user_id).await?;

    let mut stages_by_technique = assemble_stages(stages, phases, &limits)?;

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
        limits: Some(limits_to_proto(&limits)?),
    })
}

/// Stores a draft and returns it as the catalogue would describe it.
pub async fn create(
    pool: &PgPool,
    user_id: UserId,
    draft: Option<pb::TechniqueDraft>,
) -> Result<pb::CreateUserTechniqueResponse, UserTechniqueError> {
    let limits = repository::phase_limits(pool).await?;
    let authored = validate(draft, &limits)?;

    // Counted before the insert rather than enforced by a constraint: "you have
    // twenty already" is a sentence a person can act on, where a unique-violation
    // turned into `internal` is one nobody can.
    let held = repository::count(pool, user_id).await?;
    if held >= i64::from(MAX_TECHNIQUES) {
        return Err(UserTechniqueError::TooMany(format!(
            "you can keep {MAX_TECHNIQUES} of your own exercises — delete one to make room"
        )));
    }

    let id = repository::insert(pool, user_id, &authored).await?;

    Ok(pb::CreateUserTechniqueResponse {
        technique: Some(authored_to_proto(id, &authored, &limits)?),
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
) -> Result<pb::UpdateUserTechniqueResponse, UserTechniqueError> {
    let id = parse_id(id)?;
    let limits = repository::phase_limits(pool).await?;
    let authored = validate(draft, &limits)?;

    repository::replace(pool, user_id, id, &authored).await?;

    Ok(pb::UpdateUserTechniqueResponse {
        technique: Some(authored_to_proto(id, &authored, &limits)?),
    })
}

/// Deletes a technique this person owns, or one they never had.
pub async fn delete(
    pool: &PgPool,
    user_id: UserId,
    id: &str,
) -> Result<pb::DeleteUserTechniqueResponse, UserTechniqueError> {
    let id = parse_id(id)?;
    repository::delete(pool, user_id, id).await?;

    Ok(pb::DeleteUserTechniqueResponse {})
}

fn parse_id(id: &str) -> Result<Uuid, UserTechniqueError> {
    Uuid::parse_str(id)
        .map_err(|_| UserTechniqueError::Invalid(format!("`{id}` is not a technique id")))
}
