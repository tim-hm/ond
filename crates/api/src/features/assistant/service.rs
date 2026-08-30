//! Business logic — decides whether a model is asked at all, checks what it
//! says, and answers regardless. Explicit dependencies, never `Arc<AppState>`,
//! zero raw queries. Every RPC runs the same three steps: claim a call
//! against the daily allowance, ask the model, believe as little of the
//! answer as possible — any declining step hands over to `super::fallback`.

use std::sync::Arc;

use sqlx::PgPool;

use super::errors::AssistantError;
use super::model::{ModelClient, ModelRequest, ModelStream};
use super::stream::{
    ChatStream, chat_from_model, conversation, fixed_reply, with_offer_annotations,
};
use super::types::{
    CHAT_MAX_TOKENS, HealthContext, RECOMMENDATION_MAX_TOKENS, Recommendation, daily_model_calls,
};
use super::{fallback, metrics, parse, prompt, repository, tools};
use crate::features::entitlement::service as entitlement;
use crate::features::entitlement::types::Tier;
use crate::features::journey::sessions::service as journey;
use crate::features::journey::sessions::types::PracticeSnapshot;
use crate::features::profile::service as profile;
use crate::features::profile::types::ProfileSnapshot;
use crate::features::technique::cache::CuratedCache;
use crate::features::technique::types::{Reference, Technique};
use crate::features::user_technique::service as user_technique;
use crate::features::user_technique::types::{PhaseLimits, SavedSummary};
use crate::identity::UserId;
use crate::proto::ond::v1 as pb;

/// Three techniques to try next, with a sentence each. Always answers: an
/// unconfigured, over-quota, breaker-tripped, failing, or unusable model all
/// land on the same rule-based list, as does a tier that buys no call. The
/// response's `source` separates that last one (see [`Claim`]), so a client
/// can be honest about which it got without guessing from the words.
pub async fn get_recommendation(
    pool: &PgPool,
    model: &dyn ModelClient,
    curated: &CuratedCache,
    user_id: UserId,
    health: Option<pb::HealthContext>,
) -> Result<pb::GetRecommendationResponse, AssistantError> {
    let context = read_context(pool, curated, user_id, None).await?;

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

/// Everything an RPC here reads before deciding anything. One struct rather
/// than a tuple because both RPCs thread it whole, and a four-way tuple at
/// two call sites is four positional facts nobody can name at a glance.
struct Context {
    /// Refcounts into `technique`'s process-lifetime cache rather than copies:
    /// the chat's reply stream outlives the call that read them.
    catalogue: Arc<Vec<Technique>>,
    /// The occasions, the progression, and the foundation headings — the
    /// curated routes the coach names so that it and the app's own screens
    /// agree.
    reference: Arc<Reference>,
    profile: ProfileSnapshot,
    practice: PracticeSnapshot,
    tier: Tier,
    /// The exercises this person has built for themselves, so the coach can
    /// name one back to them and stop offering to save what they already keep.
    saved: Vec<SavedSummary>,
}

/// Reads the [`Context`], concurrently — none of the reads depends on the
/// others, and serialising them would sum their round-trips. The widest
/// fan-out in the crate, bounded by the pool rather than the database, so
/// what each branch costs in connections is the thing to watch (the curated
/// branch costs none once warm). `utc_offset_minutes` feeds only the streak.
async fn read_context(
    pool: &PgPool,
    cache: &CuratedCache,
    user_id: UserId,
    utc_offset_minutes: Option<i32>,
) -> Result<Context, AssistantError> {
    let (curated, profile, practice, tier, saved) = tokio::try_join!(
        async { cache.get(pool).await.map_err(AssistantError::from) },
        async {
            profile::snapshot(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
        async {
            journey::practice_snapshot(pool, user_id, utc_offset_minutes)
                .await
                .map_err(AssistantError::from)
        },
        async {
            entitlement::tier(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
        async {
            user_technique::saved_summaries(pool, user_id)
                .await
                .map_err(AssistantError::from)
        },
    )?;

    Ok(Context {
        catalogue: Arc::clone(&curated.catalogue),
        reference: Arc::clone(&curated.reference),
        profile,
        practice,
        tier,
        saved,
    })
}

/// The model's answer to an already-claimed call, or `None` if it did not
/// produce a usable one. Collapsing "call failed" and "reply unusable" into
/// one `None` is deliberate: the caller does the same thing in both, and both
/// are outages from the reader's side. Whether the call was *allowed* is
/// settled before this — see [`Claim`], the distinction that must survive.
async fn model_recommendations(
    model: &dyn ModelClient,
    context: &Context,
    health: Option<&HealthContext>,
) -> Option<Vec<Recommendation>> {
    let request = ModelRequest {
        cacheable_prefix: prompt::catalogue_prefix(&context.catalogue, &context.reference),
        instruction: prompt::recommendation_instruction(
            &context.profile,
            &context.practice,
            &context.catalogue,
            &context.saved,
            health,
        ),
        turns: Vec::new(),
        tools: Vec::new(),
        max_tokens: RECOMMENDATION_MAX_TOKENS,
    };

    let reply = match model.complete(&request).await {
        Ok(reply) => reply,
        Err(error) => {
            tracing::warn!(feature = "assistant", %error, "falling back to the rules");
            metrics::fell_back(metrics::Fallback::ModelError);
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
        metrics::fell_back(metrics::Fallback::NoTechnique);
        return None;
    }

    metrics::answered();
    Some(recommendations)
}

/// The coach's reply to one message, streamed a chunk at a time. Stateless on
/// purpose: the transcript lives on the device and arrives as `history`; the
/// only write is the quota claim. Every failure short of a malformed request
/// streams one fixed reply, flagged `FALLBACK` or `SUBSCRIPTION_REQUIRED`; a
/// model failing *mid-answer* ends the stream `UNAVAILABLE`, never complete-looking.
pub async fn chat(
    pool: &PgPool,
    model: &dyn ModelClient,
    curated: &CuratedCache,
    user_id: UserId,
    request: pb::ChatRequest,
    limits: Arc<PhaseLimits>,
) -> Result<ChatStream, AssistantError> {
    // Shape first, so a malformed request is refused before it writes a quota
    // row or reads anything at all.
    let turns = conversation(request.history, &request.message)?;

    // Read even when the model is plainly unavailable: which fixed reply to
    // send is a question about the caller's tier, and the tier is in the
    // context. While the assistant is free this read buys nothing — kept so
    // the ordering is not deleted and rediscovered when the gate returns.
    let context = read_context(pool, curated, user_id, request.utc_offset_minutes).await?;
    let health = clamp_health(request.health_context);
    let turns = with_offer_annotations(turns, &context.catalogue);

    let stream = claimed_stream(
        pool,
        model,
        user_id,
        context.tier,
        || ModelRequest {
            cacheable_prefix: prompt::catalogue_prefix(&context.catalogue, &context.reference),
            instruction: prompt::chat_instruction(
                &context.profile,
                &context.practice,
                &context.catalogue,
                &context.saved,
                health.as_ref(),
            ),
            turns,
            // The one RPC that declares tools: a conversation can settle on
            // something worth doing now; a ranked list cannot. All are
            // terminal proposals the person accepts by
            // tapping — at most one of them per reply, which `chat_from_model`
            // enforces.
            tools: tools::specs(),
            max_tokens: CHAT_MAX_TOKENS,
        },
        "falling back to the fixed reply",
    )
    .await;

    Ok(match stream {
        Ok(chunks) => chat_from_model(chunks, context.catalogue, limits),
        Err(source) => fixed_reply(source),
    })
}

/// Claims a call and opens the model's stream, or says how a fallback answer
/// should be flagged; building the answer stays with the caller. The request
/// arrives as a closure because the claim covers availability too: a process
/// with no credentials neither writes a quota row nor builds a prompt for a
/// call that provably will not be made.
async fn claimed_stream(
    pool: &PgPool,
    model: &dyn ModelClient,
    user_id: UserId,
    tier: Tier,
    request: impl FnOnce() -> ModelRequest,
    falling_back: &'static str,
) -> Result<ModelStream, pb::AssistantSource> {
    let claim = claim_call(pool, model, user_id, tier).await;
    if claim == Claim::Granted {
        match model.stream(&request()).await {
            Ok(chunks) => {
                // Establishment, not completion: a stream that fails after its
                // first chunk is counted here as answered, because from the
                // reader's side it was. `ond_grpc_requests_total` carries that
                // call's terminal status, which is where a mid-stream failure
                // shows up.
                metrics::answered();
                return Ok(chunks);
            }
            Err(error) => {
                tracing::warn!(feature = "assistant", %error, "{falling_back}");
                metrics::fell_back(metrics::Fallback::StreamFailed);
            }
        }
    }

    Err(claim.fallback_source())
}

/// Whether one model call may be spent, and when not, whether waiting would
/// help. Two refusals rather than one `false` because they want opposite copy
/// and the client cannot work out which it got — collapsing them had the
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

/// Claims one call against the daily allowance. `tier` comes from the row,
/// never the request — the one place a client could talk the server into
/// spending money. Tier settles before availability: only it stays true after
/// an outage. Both refusals return before the write — no charge for a call never
/// made — and a database failure reads as "no allowance"; the fallback survives.
async fn claim_call(pool: &PgPool, model: &dyn ModelClient, user_id: UserId, tier: Tier) -> Claim {
    // Each refusal records its own reason on the way past. `Claim` collapses
    // three of them into `Unavailable` because the caller behaves identically in
    // all three, which is right for control flow and useless to an operator: a
    // provider outage and a heavy user finishing their allowance arrive at the
    // same variant, and only one of them is worth being woken for.
    let Some(limit) = daily_model_calls(tier) else {
        metrics::fell_back(metrics::Fallback::SubscriptionRequired);
        return Claim::SubscriptionRequired;
    };

    if !model.is_available() {
        metrics::fell_back(metrics::Fallback::ProviderUnavailable);
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
            metrics::fell_back(metrics::Fallback::AllowanceSpent);
            Claim::Unavailable
        }
        Err(error) => {
            tracing::error!(feature = "assistant", %error, "could not claim a model call");
            metrics::fell_back(metrics::Fallback::ClaimFailed);
            Claim::Unavailable
        }
    }
}

/// The wire health context as the domain type, clamped, or `None` when
/// nothing usable was sent. The only place the wire message is read; nothing
/// persists or formats the value ([`HealthContext`] deliberately cannot be).
/// The prost message derives `Debug`, so it must never be handed to `tracing`
/// — keeping the conversion at the top of each RPC keeps its scope small.
fn clamp_health(health: Option<pb::HealthContext>) -> Option<HealthContext> {
    health.and_then(|context| {
        HealthContext::clamped(
            (context.resting_hr_bpm, context.resting_hr_trend_bpm),
            (context.hrv_sdnn_ms, context.hrv_sdnn_trend_ms),
            (
                context.sleeping_breaths_per_minute,
                context.sleeping_breaths_trend,
            ),
        )
    })
}

fn to_proto(recommendation: Recommendation) -> pb::Recommendation {
    pb::Recommendation {
        technique_slug: recommendation.technique_slug.into_string(),
        reason: recommendation.reason,
    }
}
