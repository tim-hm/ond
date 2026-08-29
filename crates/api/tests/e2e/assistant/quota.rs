//! What stops the assistant spending: the daily allowance both RPCs share,
//! and the breaker that stops calling a provider which keeps failing.
//!
//! Both are asserted through the model's call count, because an allowance that
//! never bound and a breaker that never opened both still return an answer.

use std::sync::Arc;
use std::time::Duration;

use api::assistant::{GuardedModelClient, ModelError};
use api::entitlement::Tier;
use api::proto::ond::v1 as pb;

use super::fixtures::{OTHER_USER, USER, chat, recommend};
use crate::harness::{ScriptedModel, TestDatabase, allowance};

/// The quota is a spend ceiling that has to bind, and its exhaustion must be a
/// degraded answer rather than an error: the person asked a question and gets
/// one, flagged — without the flag a client would present rule-based copy as
/// personalised. The ceiling is a subscriber's: the tier decides whether there
/// is a pool, and the day's count decides what is left of it.
#[tokio::test]
async fn an_exhausted_quota_answers_from_the_rules() {
    let db = TestDatabase::create("assistant_quota").await;
    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));
    let allowance = allowance(Tier::Plus);

    for _ in 0..allowance {
        let response = recommend(&db, model.clone(), USER).await;
        assert_eq!(response.source, pb::AssistantSource::Model as i32);
    }

    let exhausted = recommend(&db, model.clone(), USER).await;
    assert_eq!(exhausted.source, pb::AssistantSource::Fallback as i32);
    assert!(!exhausted.recommendations.is_empty());

    assert_eq!(
        model.calls(),
        allowance,
        "the call past the limit must not reach the model at all"
    );

    // The allowance is per person, so somebody else is unaffected by it — the
    // counter being keyed on the caller is what stops one heavy user from
    // silencing the assistant for everybody.
    let other = recommend(&db, model, OTHER_USER).await;
    assert_eq!(other.source, pb::AssistantSource::Model as i32);
}

/// The breaker's whole purpose: stop paying for a provider that is down, and
/// start again once it might not be. Both halves are asserted through the call
/// count, because a breaker that never opened and one that never closed both
/// still return an answer.
///
#[tokio::test]
async fn the_breaker_trips_and_then_recovers() {
    let db = TestDatabase::create("assistant_breaker").await;

    let model = ScriptedModel::script(vec![
        Err(ModelError::Failed("first".to_owned())),
        Err(ModelError::Failed("second".to_owned())),
        Err(ModelError::Failed("third".to_owned())),
        Ok("box-breathing | Back up.".to_owned()),
    ]);
    // Three failures to trip, and a cooldown short enough to wait out inside a
    // test — the production policy is a minute, which is not a thing to sleep
    // through here.
    let guarded = Arc::new(GuardedModelClient::with_policy(
        model.clone(),
        3,
        Duration::from_millis(150),
    ));

    for _ in 0..3 {
        let response = recommend(&db, guarded.clone(), USER).await;
        assert_eq!(response.source, pb::AssistantSource::Fallback as i32);
    }
    assert_eq!(model.calls(), 3, "three failures reach the model");

    let while_open = recommend(&db, guarded.clone(), USER).await;
    assert_eq!(while_open.source, pb::AssistantSource::Fallback as i32);
    assert_eq!(
        model.calls(),
        3,
        "the fourth call is refused without reaching the model"
    );

    tokio::time::sleep(Duration::from_millis(200)).await;

    let recovered = recommend(&db, guarded, USER).await;
    assert_eq!(recovered.source, pb::AssistantSource::Model as i32);
    assert_eq!(model.calls(), 4, "the cooldown lets one call through");
}

/// Chat and recommendations draw on one shared pool: interleaved calls spend
/// it together, the call past the ceiling answers `FALLBACK` on either RPC,
/// and the model is never asked again that day.
#[tokio::test]
async fn chat_and_recommendations_share_one_daily_pool() {
    let db = TestDatabase::create("assistant_chat_quota").await;
    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));
    let allowance = allowance(Tier::Plus);

    for call in 0..allowance {
        if call % 2 == 0 {
            let chunks = chat(&db, model.clone(), USER, Vec::new(), "and then?")
                .await
                .into_ok();
            assert_eq!(chunks[0].source, pb::AssistantSource::Model as i32);
        } else {
            let response = recommend(&db, model.clone(), USER).await;
            assert_eq!(response.source, pb::AssistantSource::Model as i32);
        }
    }

    let exhausted_chat = chat(&db, model.clone(), USER, Vec::new(), "and then?")
        .await
        .into_ok();
    assert_eq!(
        exhausted_chat[0].source,
        pb::AssistantSource::Fallback as i32,
        "an exhausted pool answers chat with the fixed reply"
    );

    let exhausted_recommendation = recommend(&db, model.clone(), USER).await;
    assert_eq!(
        exhausted_recommendation.source,
        pb::AssistantSource::Fallback as i32,
        "the same spent pool degrades recommendations too"
    );

    assert_eq!(
        model.calls(),
        allowance,
        "nothing past the ceiling reaches the model"
    );
}
