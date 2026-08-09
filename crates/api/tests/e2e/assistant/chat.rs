//! `Chat`: the streamed reply, the transcript's journey to the model as
//! attributed turns, the bounds that refuse a request unspent, and the two
//! fixed replies a caller gets when no model answers.

use std::sync::Arc;

use api::assistant::{ChatRole, ModelError};
use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;

use super::fixtures::{CHAT, HalfAnswer, USER, chat, chat_turn, recommend, set_goals};
use crate::harness::{ScriptedModel, TestDatabase, call_grpc_web_stream_with, subscribe};

/// The coach has to talk to somebody who named no goal without inventing one
/// for them. The profile block says so in as many words — an absence stated is
/// what stops the model filling it in — and the reply still streams.
#[tokio::test]
async fn the_coach_is_told_plainly_when_no_goal_was_named() {
    let db = TestDatabase::create("assistant_chat_no_goals").await;
    set_goals(&db, USER, &[]).await;
    let model = ScriptedModel::always(Ok("Start with a longer exhale.".to_owned()));

    let chunks = chat(&db, model.clone(), USER, Vec::new(), "where do I start?")
        .await
        .into_ok();

    assert!(!chunks.is_empty());
    for chunk in &chunks {
        assert_eq!(
            chunk.source,
            pb::AssistantSource::Model as i32,
            "an empty goal set is answerable, not a reason to degrade"
        );
    }

    let requests = model.requests();
    assert_eq!(requests.len(), 1);
    assert!(
        requests[0]
            .instruction
            .contains("goals, in their own order: they have not said"),
        "an unanswered goals question is stated, never guessed at"
    );
}

/// The chat reply rides the same chunked pipe as the explanation: frames in
/// the order the model wrote them, `MODEL` on every one, concatenating back
/// into the whole reply.
#[tokio::test]
async fn the_chat_reply_streams_ordered_chunks() {
    let db = TestDatabase::create("assistant_chat_streaming").await;
    let model = ScriptedModel::always(Ok("A longer exhale settles you.\n\
         Try extended-exhale tonight."
        .to_owned()));

    let chunks = chat(&db, model, USER, Vec::new(), "What helps with sleep?")
        .await
        .into_ok();

    assert!(chunks.len() > 1, "the reply arrives as it is written");
    for chunk in &chunks {
        assert_eq!(chunk.source, pb::AssistantSource::Model as i32);
    }
    let text: String = chunks
        .iter()
        .map(|chunk| chunk.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    assert_eq!(
        text,
        "A longer exhale settles you.\nTry extended-exhale tonight."
    );
}

/// The conversation reaches the model as attributed turns — real user and
/// assistant messages — and never as text serialised into the instruction,
/// which is the injection posture the seam's `turns` field exists for. The
/// prefix a chat call sends is byte-identical to a recommendation's, so the
/// three RPCs share one provider cache entry.
#[tokio::test]
async fn the_conversation_arrives_as_turns_not_as_instruction_text() {
    let db = TestDatabase::create("assistant_chat_turns").await;
    let model = ScriptedModel::always(Ok("box-breathing | Steady.".to_owned()));

    let history = vec![
        chat_turn(pb::ChatRole::Person, "I keep waking at 3am"),
        chat_turn(pb::ChatRole::Coach, "A longer exhale before bed can help."),
    ];
    chat(&db, model.clone(), USER, history, "Which exercise, then?")
        .await
        .into_ok();
    recommend(&db, model.clone(), USER).await;

    let requests = model.requests();
    assert_eq!(requests.len(), 2);

    let turns = &requests[0].turns;
    assert_eq!(turns.len(), 3, "two history turns plus the message");
    assert_eq!(turns[0].role, ChatRole::Person);
    assert_eq!(turns[0].text, "I keep waking at 3am");
    assert_eq!(turns[1].role, ChatRole::Coach);
    assert_eq!(turns[2].role, ChatRole::Person);
    assert_eq!(turns[2].text, "Which exercise, then?");

    for spoken in ["I keep waking at 3am", "Which exercise, then?"] {
        assert!(
            !requests[0].instruction.contains(spoken),
            "`{spoken}` must travel as a turn, never inside the instruction"
        );
        assert!(
            !requests[0].cacheable_prefix.contains(spoken),
            "`{spoken}` is personal and must stay out of the cached prefix"
        );
    }

    assert_eq!(
        requests[0].cacheable_prefix, requests[1].cacheable_prefix,
        "chat and recommendation share one prefix, or the provider cache is dead"
    );
    assert!(
        requests[1].turns.is_empty(),
        "the one-shot RPCs carry no turns"
    );
}

/// Truncation is observable from outside: a transcript deeper than the limit
/// reaches the model with only its newest turns, silently, and the request
/// still succeeds.
#[tokio::test]
async fn a_deep_history_is_truncated_to_its_newest_turns() {
    let db = TestDatabase::create("assistant_chat_truncation").await;
    let model = ScriptedModel::always(Ok("Steady on.".to_owned()));

    let history: Vec<pb::ChatTurn> = (0..25)
        .map(|index| chat_turn(pb::ChatRole::Person, &format!("turn-{index}")))
        .collect();
    chat(&db, model.clone(), USER, history, "still with me?")
        .await
        .into_ok();

    let requests = model.requests();
    let turns = &requests[0].turns;
    assert_eq!(
        turns.len(),
        21,
        "twenty kept history turns plus the message"
    );
    assert_eq!(turns[0].text, "turn-5", "the oldest five are dropped");
    assert_eq!(turns.last().expect("the message").text, "still with me?");
}

/// Bounds are refused before anything is spent: an over-long message and an
/// over-long history turn are both `INVALID_ARGUMENT`, and the model is never
/// asked.
#[tokio::test]
async fn an_out_of_bounds_chat_is_refused_unspent() {
    let db = TestDatabase::create("assistant_chat_bounds").await;
    let model = ScriptedModel::always(Ok("never sent".to_owned()));

    let over_long = "x".repeat(1001);
    let refused = chat(&db, model.clone(), USER, Vec::new(), &over_long).await;
    assert_eq!(refused.status, tonic::Code::InvalidArgument as i32);
    assert!(refused.messages.is_empty());

    let bad_history = vec![chat_turn(pb::ChatRole::Person, &over_long)];
    let refused = chat(&db, model.clone(), USER, bad_history, "hello").await;
    assert_eq!(refused.status, tonic::Code::InvalidArgument as i32);

    assert_eq!(
        model.calls(),
        0,
        "a refused request never reaches the model"
    );
}

/// Below Coach the conversation still answers — a fixed reply flagged
/// `SUBSCRIPTION_REQUIRED`, with no model call and no quota row. "Every RPC
/// answers" applies to chat exactly as it does to the other two.
///
/// The sentence must not send them round a loop that cannot close. Somebody on
/// Plus who is told to ask again later will ask, wait, ask again, and conclude
/// the app is broken — which is what happened, on a device, to the person who
/// commissioned the paywall.
#[tokio::test]
async fn chat_below_coach_is_told_it_is_a_subscription() {
    let db = TestDatabase::create("assistant_chat_tier").await;
    let model = ScriptedModel::always(Ok("never sent".to_owned()));

    subscribe(&db.pool, USER, "PLUS").await;
    let chunks: Vec<pb::ChatResponse> = call_grpc_web_stream_with(
        db.app_with_model(model.clone()),
        CHAT,
        &pb::ChatRequest {
            history: Vec::new(),
            message: "hello coach".to_owned(),
            health_context: None,
        },
        &[(USER_ID_HEADER, USER)],
    )
    .await
    .into_ok();

    assert!(!chunks.is_empty());
    for chunk in &chunks {
        assert_eq!(
            chunk.source,
            pb::AssistantSource::SubscriptionRequired as i32
        );
    }

    let reply: String = chunks.iter().map(|chunk| chunk.text.as_str()).collect();
    assert!(
        reply.contains("Coach"),
        "the reply must name the subscription: {reply}"
    );
    assert!(
        !reply.contains("again later"),
        "no retry can ever succeed for this caller: {reply}"
    );
    assert_eq!(model.calls(), 0);
}

/// The other half of the pair, and the reason it is a pair: a Coach subscriber
/// whose model call fails gets an outage, worded as one, flagged `FALLBACK`.
///
/// Asserted alongside the test above rather than on its own, because what is
/// being guarded is that the two differ. One string serving both refusals is
/// the failure mode, and neither sentence read in isolation would catch it.
#[tokio::test]
async fn chat_above_coach_reads_a_failure_as_an_outage() {
    let db = TestDatabase::create("assistant_chat_outage").await;
    let model = ScriptedModel::always(Err(ModelError::Failed("down".to_owned())));

    let chunks = chat(&db, model.clone(), USER, Vec::new(), "hello coach")
        .await
        .into_ok();

    assert!(!chunks.is_empty());
    for chunk in &chunks {
        assert_eq!(chunk.source, pb::AssistantSource::Fallback as i32);
    }

    let reply: String = chunks.iter().map(|chunk| chunk.text.as_str()).collect();
    assert!(
        reply.contains("again later"),
        "an outage passes, so the reply invites a retry: {reply}"
    );
    assert!(
        !reply.contains("subscription"),
        "they have already paid; do not sell to them: {reply}"
    );
}

/// A reply that dies mid-answer keeps what arrived and ends with a status,
/// exactly as the explanation stream does: the person is reading it, and an
/// ended stream must be distinguishable from a finished one.
#[tokio::test]
async fn a_broken_chat_stream_keeps_arrived_text() {
    let db = TestDatabase::create("assistant_chat_broken_stream").await;

    let response = chat(&db, Arc::new(HalfAnswer), USER, Vec::new(), "hello").await;

    assert_eq!(response.status, tonic::Code::Unavailable as i32);
    assert_eq!(
        response.messages.len(),
        1,
        "the chunk that arrived before the failure still reaches the client"
    );
    assert_eq!(response.messages[0].text, "First the mechanism.");
    assert_eq!(
        response.messages[0].source,
        pb::AssistantSource::Model as i32
    );
}

/// The chat path's own paid check, on `smoke_the_real_model_answers`'s exact
/// terms — `#[ignore]`d everywhere but `mise run assistant:smoke`, skipping
/// without AWS credentials.
///
/// What it proves that the first smoke cannot: the turns emission in
/// `bedrock` — the instruction message followed by genuine alternating
/// user/assistant messages, consecutive same-role messages included — is a
/// shape the provider accepts and streams an answer to. Every deterministic
/// test stops at the seam; this is the only check of the layer under it.
#[tokio::test]
#[ignore = "calls the real model provider; run it with `mise run assistant:smoke`"]
// The whole output of this test is what it printed — a status line nobody reads
// is not a smoke test.
#[allow(clippy::print_stdout)]
async fn smoke_the_real_model_chats() {
    let client = match api::assistant::BedrockClient::connect().await {
        Ok(client) => client,
        Err(error) => {
            println!("no AWS credentials — nothing to smoke-test ({error})");
            return;
        }
    };

    let db = TestDatabase::create("assistant_smoke_chat").await;
    set_goals(&db, USER, &[pb::TechniqueGoal::Sleep]).await;

    let history = vec![
        chat_turn(pb::ChatRole::Person, "I keep waking up around 3am."),
        chat_turn(
            pb::ChatRole::Coach,
            "A longer exhale before bed can help — it lengthens the parasympathetic phase.",
        ),
    ];
    let chunks = chat(
        &db,
        Arc::new(client),
        USER,
        history,
        "Which exercise should I try tonight?",
    )
    .await
    .into_ok();

    let text: String = chunks.iter().map(|chunk| chunk.text.as_str()).collect();
    println!("model:  {}", api::config::BEDROCK_MODEL_ID);
    println!("chunks: {}", chunks.len());
    let preview: String = text.chars().take(180).collect();
    println!("reply:  {preview}…");

    assert!(!text.trim().is_empty(), "the reply carries text");
    assert_eq!(
        chunks[0].source,
        pb::AssistantSource::Model as i32,
        "the provider answered but the call fell back — see the warning above"
    );
}
