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
use super::types::{MAX_TECHNIQUES, PhaseLimits};
use super::validation::validate;
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// Whether this draft is one this feature would accept, for another feature
/// that is about to propose it.
///
/// The assistant's save-this-pattern card carries a draft the person accepts by
/// tapping, and the tap calls [`create`]. Running the proposal through the same
/// validator first is what makes the card honest: the server can never offer to
/// save something the create RPC would then refuse. On the service rather than a
/// reach into `super::validation`, which is private — the rule is this feature's
/// and so is the way to ask about it.
///
/// Discards the validated value. A caller here wants the verdict, and the draft
/// it holds is the thing it will send back.
pub fn validate_draft(
    draft: pb::TechniqueDraft,
    limits: &PhaseLimits,
) -> Result<(), UserTechniqueError> {
    validate(Some(draft), limits).map(|_| ())
}

/// This person's techniques, and the limits a composer has to work inside.
///
/// `limits` arrives from the handler's [`repository::PhaseLimitsCache`] rather
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
    let id = parse_id(id)?;
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
    let id = parse_id(id)?;
    repository::delete(pool, user_id, id).await?;

    Ok(pb::DeleteUserTechniqueResponse {})
}

fn parse_id(id: &str) -> Result<Uuid, UserTechniqueError> {
    Uuid::parse_str(id)
        .map_err(|_| UserTechniqueError::Invalid(format!("`{id}` is not a technique id")))
}
