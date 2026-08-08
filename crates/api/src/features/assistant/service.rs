//! Business logic — decides whether a model is asked at all, checks what it
//! says, and answers regardless.
//!
//! Receives explicit dependencies (`&PgPool`, `&dyn ModelClient`), never
//! `Arc<AppState>`, and contains zero raw queries.
//!
//! Every RPC runs the same three steps, in this order: claim a call against the
//! caller's daily allowance, ask the model, believe as little of the answer as
//! possible. Any step declining hands over to `super::fallback`, and the
//! response says so. Getting either answer onto a tonic stream is
//! `super::stream`.

use sqlx::PgPool;

use super::errors::AssistantError;
use super::model::{ModelClient, ModelRequest};
use super::stream::{
    ChatStream, ExplanationStream, chat_from_model, conversation, fixed_reply, from_fallback,
    from_model,
};
use super::types::{
    CHAT_MAX_TOKENS, EXPLANATION_MAX_TOKENS, HealthContext, RECOMMENDATION_MAX_TOKENS,
    Recommendation, daily_model_calls,
};
use super::{fallback, parse, prompt, repository};
use crate::features::entitlement::service as entitlement;
use crate::features::entitlement::types::Tier;
use crate::features::journey::sessions::service as journey;
use crate::features::journey::sessions::types::PracticeSnapshot;
use crate::features::profile::service as profile;
use crate::features::profile::types::ProfileSnapshot;
use crate::features::technique::service as technique;
use crate::features::technique::types::{Technique, resolve};
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// Three techniques to try next, with a sentence each.
///
/// Always answers. A model that is unconfigured, over quota, behind a tripped
/// breaker, failing, or replying with nothing this server recognises all land on
/// the same rule-based list, and so does a caller whose tier buys no model call
/// at all. The response's `source` separates that last one from the rest — see
/// [`Claim`] — so a client can be honest about which it got without having to
/// guess from the words.
pub async fn get_recommendation(
    pool: &PgPool,
    model: &dyn ModelClient,
    user_id: UserId,
    health: Option<pb::HealthContext>,
) -> Result<pb::GetRecommendationResponse, AssistantError> {
    let context = read_context(pool, user_id).await?;
    if context.catalogue.is_empty() {
        return Err(AssistantError::EmptyCatalogue);
    }

    let health = clamp_health(health);
    let claim = claim_call(pool, model, user_id, context.tier).await;
    let written = if claim == Claim::Granted {
        model_recommendations(model, &context, health.as_ref()).await
    } else {
        None
    };

    let (recommendations, source) = match written {
        Some(recommendations) => (recommendations, pb::AssistantSource::Model),
        None => (
            fallback::recommendations(&context.catalogue, &context.profile, &context.practice),
            claim.fallback_source(),
        ),
    };

    Ok(pb::GetRecommendationResponse {
        recommendations: recommendations.into_iter().map(to_proto).collect(),
        source: source as i32,
    })
}

/// Everything an RPC here reads before deciding anything: the catalogue, the
/// caller's profile, their recent practice, and what they are entitled to.
///
/// One struct rather than a tuple because three RPCs now thread it whole, and
/// a four-way tuple at three call sites is four positional facts nobody can
/// name at a glance.
struct Context {
    catalogue: Vec<Technique>,
    profile: ProfileSnapshot,
    practice: PracticeSnapshot,
    tier: Tier,
}

/// Reads the [`Context`], concurrently.
///
/// Concurrently because none of the four reads depends on the others, and all
/// of them happen before anything else can: serialising them would put four
/// loopback round-trips in front of every call rather than one. The
/// entitlement joins them rather than being read where it is used, for exactly
/// that reason — it decides the model allowance, which is the last thing any
/// RPC settles.
async fn read_context(pool: &PgPool, user_id: UserId) -> Result<Context, AssistantError> {
    let (catalogue, profile, practice, tier) = tokio::try_join!(
        async {
            technique::catalogue(pool)
                .await
                .map_err(AssistantError::from)
        },
        async {
            profile::snapshot(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
        async {
            journey::practice_snapshot(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
        async {
            entitlement::tier(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
    )?;

    Ok(Context {
        catalogue,
        profile,
        practice,
        tier,
    })
}

/// The model's answer to an already-claimed call, or `None` if it did not
/// produce a usable one.
///
/// Collapsing "call failed" and "reply was unusable" into one `None` is
/// deliberate: the caller does the same thing in both cases, and both are
/// outages from the reader's side. Whether the call was *allowed* is settled
/// before this is reached — see [`Claim`], which is the distinction that has to
/// survive.
async fn model_recommendations(
    model: &dyn ModelClient,
    context: &Context,
    health: Option<&HealthContext>,
) -> Option<Vec<Recommendation>> {
    let request = ModelRequest {
        cacheable_prefix: prompt::catalogue_prefix(&context.catalogue),
        instruction: prompt::recommendation_instruction(
            &context.profile,
            &context.practice,
            &context.catalogue,
            health,
        ),
        turns: Vec::new(),
        max_tokens: RECOMMENDATION_MAX_TOKENS,
    };

    let reply = match model.complete(&request).await {
        Ok(reply) => reply,
        Err(error) => {
            tracing::warn!(feature = "assistant", %error, "falling back to the rules");
            return None;
        }
    };

    // The guard: a slug reaches a client only because the catalogue has it.
    let recommendations = parse::parse_recommendations(&reply, &context.catalogue);
    if recommendations.is_empty() {
        tracing::warn!(
            feature = "assistant",
            "the reply named no technique in the catalogue; falling back to the rules"
        );
        return None;
    }

    Some(recommendations)
}

/// Why one technique works, streamed a chunk at a time.
///
/// Answers for any slug the catalogue holds and `NOT_FOUND` for one it does not,
/// which is the only failure a caller can act on. Falls back on the same terms
/// as [`get_recommendation`], and the fallback is chunked down the same pipe so
/// the client has one accumulate-and-render path rather than two.
///
/// A model that fails *mid-answer* ends the stream with `UNAVAILABLE` rather
/// than switching to the fallback text: the person is looking at half an
/// explanation, and a second voice picking up the sentence is worse than a
/// visible stop.
pub async fn explain_technique(
    pool: &PgPool,
    model: &dyn ModelClient,
    user_id: UserId,
    slug: &str,
    health: Option<pb::HealthContext>,
) -> Result<ExplanationStream, AssistantError> {
    let context = read_context(pool, user_id).await?;
    let technique = resolve(&context.catalogue, slug).ok_or_else(|| {
        AssistantError::UnknownTechnique(format!("no technique has the slug `{slug}`"))
    })?;

    let health = clamp_health(health);

    // The claim covers availability as well as the tier, so a process with no
    // key configured — a fresh clone, CI, the whole e2e suite — neither writes
    // a quota row nor builds a prompt for a call that provably will not be
    // made.
    let claim = claim_call(pool, model, user_id, context.tier).await;
    if claim == Claim::Granted {
        let request = ModelRequest {
            cacheable_prefix: prompt::catalogue_prefix(&context.catalogue),
            instruction: prompt::explanation_instruction(
                technique,
                &context.profile,
                &context.practice,
                &context.catalogue,
                health.as_ref(),
            ),
            turns: Vec::new(),
            max_tokens: EXPLANATION_MAX_TOKENS,
        };

        match model.stream(&request).await {
            Ok(chunks) => return Ok(from_model(chunks)),
            Err(error) => {
                tracing::warn!(feature = "assistant", %error, "falling back to the rules");
            }
        }
    }

    Ok(from_fallback(
        &fallback::explanation(technique, &context.profile, context.practice.bolt.as_ref()),
        claim.fallback_source(),
    ))
}

/// The coach's reply to one message in a conversation, streamed a chunk at a
/// time.
///
/// Stateless on purpose: the transcript lives on the device and arrives as
/// `history`, the server keeps and logs none of it, and the only thing this
/// call writes anywhere is the quota claim. Falls back on the same terms as the
/// other two RPCs — every failure short of a malformed request streams one
/// fixed sentence, [`fallback::CHAT_REPLY`] flagged `FALLBACK` for anything that
/// will pass and [`fallback::CHAT_SUBSCRIPTION_REPLY`] flagged
/// `SUBSCRIPTION_REQUIRED` for the one thing that will not — and a model that
/// fails *mid-answer* ends the stream `UNAVAILABLE`, exactly as
/// [`explain_technique`] does and for the same reason.
pub async fn chat(
    pool: &PgPool,
    model: &dyn ModelClient,
    user_id: UserId,
    history: Vec<pb::ChatTurn>,
    message: &str,
    health: Option<pb::HealthContext>,
) -> Result<ChatStream, AssistantError> {
    // Shape first, so a malformed request is refused before it writes a quota
    // row or reads anything at all.
    let turns = conversation(history, message)?;

    // Read even where the model is plainly unavailable, unlike the other
    // short-circuits here: which of the two fixed replies to send is a question
    // about the caller's tier, and the tier is in the context, so an answer
    // given without it could only ever be one of them.
    let context = read_context(pool, user_id).await?;
    let health = clamp_health(health);

    let claim = claim_call(pool, model, user_id, context.tier).await;
    if claim == Claim::Granted {
        let request = ModelRequest {
            cacheable_prefix: prompt::catalogue_prefix(&context.catalogue),
            instruction: prompt::chat_instruction(
                &context.profile,
                &context.practice,
                &context.catalogue,
                health.as_ref(),
            ),
            turns,
            max_tokens: CHAT_MAX_TOKENS,
        };

        match model.stream(&request).await {
            Ok(chunks) => return Ok(chat_from_model(chunks)),
            Err(error) => {
                tracing::warn!(feature = "assistant", %error, "falling back to the fixed reply");
            }
        }
    }

    Ok(fixed_reply(claim.fallback_source()))
}

/// Whether one model call may be spent, and when it may not, whether waiting
/// would ever help.
///
/// Two refusals rather than one `false`, because they want opposite copy and
/// the client cannot work out which it got. Collapsing them is what had the
/// coach tell somebody on Free to try again later, forever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Claim {
    /// A call is claimed against today's allowance and must now be made.
    Granted,
    /// The caller's tier buys no model call at all. Nothing about waiting
    /// changes this; only a subscription does.
    SubscriptionRequired,
    /// The tier does buy calls, but not this one: today's allowance is spent,
    /// the provider is unreachable or behind a tripped breaker, or the claim
    /// itself could not be written. All of it passes.
    Unavailable,
}

impl Claim {
    /// How a client should read a rule-based answer given under this claim.
    ///
    /// [`Granted`](Self::Granted) maps to `Fallback` rather than being
    /// unreachable: a call that was claimed and then failed, or came back
    /// unusable, is an outage from the reader's side and should read as one.
    const fn fallback_source(self) -> pb::AssistantSource {
        match self {
            Self::SubscriptionRequired => pb::AssistantSource::SubscriptionRequired,
            Self::Granted | Self::Unavailable => pb::AssistantSource::Fallback,
        }
    }
}

/// Claims one call against the caller's daily allowance.
///
/// `tier` came from the caller's own row, never from the request: this is the
/// only place in the codebase where a client could otherwise talk the server
/// into spending money. It arrives as an argument rather than being read here
/// so the rule ("only Coach, and only so often") stays in Rust where it is
/// testable, instead of inside the `WHERE` clause of the statement below.
///
/// The tier is settled *before* provider availability, and the order is
/// load-bearing. Both would refuse a caller on Free, but only one of the two
/// answers stays true after the trouble passes — and a fresh clone, CI, and any
/// box with no credentials all sit permanently in the unavailable branch, so
/// checking that first would hide the durable reason behind a transient one
/// everywhere it is cheapest to notice.
///
/// A tier that buys no model calls returns before touching the database. Not an
/// optimisation — a limit of zero would still write the usage row, leaving a
/// table full of people who were never going to be charged against it. An
/// unavailable provider returns before it too: the allowance is spent at claim
/// time, so charging for a call that provably will not be made would take a
/// subscriber's coach away for somebody else's outage.
///
/// A database failure here reads as "no allowance". The alternative — failing
/// the whole RPC — would take the fallback down with the counter, and the
/// fallback is the thing that is supposed to survive.
async fn claim_call(pool: &PgPool, model: &dyn ModelClient, user_id: UserId, tier: Tier) -> Claim {
    let Some(limit) = daily_model_calls(tier) else {
        return Claim::SubscriptionRequired;
    };

    if !model.is_available() {
        return Claim::Unavailable;
    }

    match repository::claim_daily_call(pool, user_id, limit).await {
        Ok(true) => Claim::Granted,
        Ok(false) => {
            // `debug`, not `info`: once somebody is past the ceiling this is
            // every remaining request they make that day, and a heavy user
            // would otherwise be the loudest thing in the log.
            tracing::debug!(
                feature = "assistant",
                "the caller has spent today's allowance; answering from the rules"
            );
            Claim::Unavailable
        }
        Err(error) => {
            tracing::error!(feature = "assistant", %error, "could not claim a model call");
            Claim::Unavailable
        }
    }
}

/// The wire health context as the domain type, clamped, or `None` when
/// nothing usable was sent.
///
/// This is the only place the wire message is read, and the value it produces
/// lives exactly as long as the call: nothing here or downstream persists it,
/// and nothing formats it — the domain type deliberately cannot be (see
/// [`HealthContext`]). The wire message itself derives `Debug` like every
/// prost type, so it must never be handed to `tracing` either; keeping the
/// conversion at the top of each RPC keeps its scope one screen tall.
fn clamp_health(health: Option<pb::HealthContext>) -> Option<HealthContext> {
    health.and_then(|context| {
        HealthContext::clamped(
            context.resting_hr_bpm,
            context.resting_hr_trend_bpm,
            context.hrv_sdnn_ms,
            context.hrv_sdnn_trend_ms,
        )
    })
}

fn to_proto(recommendation: Recommendation) -> pb::Recommendation {
    pb::Recommendation {
        technique_slug: recommendation.technique_slug,
        reason: recommendation.reason,
    }
}
