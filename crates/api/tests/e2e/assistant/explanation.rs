//! `ExplainTechnique`: the streaming frames, the fallback down the same pipe,
//! and the two refusals that never reach the model.

use std::sync::Arc;

use api::assistant::ModelError;
use api::proto::ond::v1 as pb;

use super::fixtures::{HalfAnswer, USER, explain};
use crate::harness::{ScriptedModel, TestDatabase};

/// The repo's first server-streaming RPC, over the real gRPC-Web framing: the
/// chunks arrive as separate message frames, in order, and concatenate back
/// into what the model wrote. A client accumulates them, so order is the whole
/// contract.
#[tokio::test]
async fn the_explanation_streams_ordered_chunks() {
    let db = TestDatabase::create("assistant_streaming").await;
    let model = ScriptedModel::always(Ok("First the mechanism.\n\
         Then what it does to you.\n\
         Then when to reach for it."
        .to_owned()));

    let chunks = explain(&db, model, USER, "box-breathing").await.into_ok();

    assert!(
        chunks.len() > 1,
        "a stream that arrived as one frame is not streaming"
    );
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
        "First the mechanism.\nThen what it does to you.\nThen when to reach for it."
    );
}

/// With no model, the same RPC still answers — in chunks, on the same path, so
/// the client's accumulate-and-render code is exercised whether or not a
/// provider was reachable.
#[tokio::test]
async fn an_unavailable_model_still_explains() {
    let db = TestDatabase::create("assistant_streaming_fallback").await;
    let model = ScriptedModel::failing(ModelError::Failed("down".to_owned()));

    let chunks = explain(&db, model, USER, "wim-hof-rounds").await.into_ok();

    assert!(
        chunks.len() > 1,
        "the fallback goes down the same chunked path, so the client's \
         accumulate-and-render code is exercised whether or not a model answered"
    );
    for chunk in &chunks {
        assert_eq!(chunk.source, pb::AssistantSource::Fallback as i32);
    }

    let text: String = chunks.iter().map(|chunk| chunk.text.as_str()).collect();
    assert!(
        text.contains("Thirty full, unforced breaths"),
        "the fallback explains from the catalogue's own summary: {text}"
    );

    // Asserted as an absence, which is unusual and deliberate. This test used
    // to require the safety note here — "never in water" — and inverting it
    // rather than deleting it is what keeps the removal a decision somebody
    // made instead of a line that quietly stopped running. Wim Hof is the
    // technique with the longest caution in the catalogue, so if any surface
    // were still appending one, this is where it would show.
    assert!(
        !text.contains("water"),
        "no per-technique caution is served while the replacement is designed: {text}"
    );
}

/// A provider that dies two sentences in ends the stream with a status rather
/// than with `OK`. What arrived still reaches the client — the person is reading
/// it — but an ended stream is otherwise indistinguishable from a finished one,
/// and the client would caption half an explanation as the whole of it.
#[tokio::test]
async fn a_broken_stream_ends_with_a_status() {
    let db = TestDatabase::create("assistant_broken_stream").await;

    let response = explain(&db, Arc::new(HalfAnswer), USER, "box-breathing").await;

    assert_eq!(response.status, tonic::Code::Unavailable as i32);
    assert_eq!(
        response.messages.len(),
        1,
        "the chunk that arrived before the failure still reaches the client"
    );
    assert_eq!(
        response.messages[0].source,
        pb::AssistantSource::Model as i32
    );
}

/// A slug the catalogue does not hold is `NOT_FOUND`, not an explanation of
/// something that does not exist. The model is never asked, which is the point:
/// the check is before the spend, not after it.
#[tokio::test]
async fn an_unknown_technique_is_not_explained() {
    let db = TestDatabase::create("assistant_unknown_technique").await;
    let model = ScriptedModel::always(Ok("anything".to_owned()));

    let response = explain(&db, model.clone(), USER, "moon-breathing").await;

    assert_eq!(response.status, tonic::Code::NotFound as i32);
    assert_eq!(model.calls(), 0);
}
