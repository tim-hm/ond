//! The wire's two streaming shapes, and everything that adapts between them and
//! the model seam.
//!
//! Inbound, a chat request's history becomes the seam's attributed turns.
//! Outbound, the seam's chunks — or the rules' paragraphs — become the tonic
//! response streams the handlers name. Both directions are transport-adjacent
//! rather than orchestration, and the outbound one carries an invariant worth
//! keeping in one place: a mid-stream failure must not present a truncated
//! answer as a complete one.

use std::pin::Pin;

use tokio_stream::{Stream, StreamExt as _};

use super::errors::AssistantError;
use super::fallback;
use super::model::{ChatRole, ChatTurn, ModelStream};
use super::types::{MAX_CHAT_MESSAGE_CHARS, MAX_CHAT_TURNS};
use crate::proto::ond::v1 as pb;

/// What the `ExplainTechnique` handler returns to tonic.
pub type ExplanationStream =
    Pin<Box<dyn Stream<Item = Result<pb::ExplainTechniqueResponse, tonic::Status>> + Send>>;

/// What the `Chat` handler returns to tonic.
pub type ChatStream = Pin<Box<dyn Stream<Item = Result<pb::ChatResponse, tonic::Status>> + Send>>;

/// The fixed reply for `source`, as a one-chunk stream.
///
/// The text and the flag are chosen together and here only, so a client reading
/// the flag and a person reading the sentence can never be told different
/// things.
pub(super) fn fixed_reply(source: pb::AssistantSource) -> ChatStream {
    let text = if source == pb::AssistantSource::SubscriptionRequired {
        fallback::CHAT_SUBSCRIPTION_REPLY
    } else {
        fallback::CHAT_REPLY
    };

    Box::pin(tokio_stream::iter(vec![Ok(pb::ChatResponse {
        text: text.to_owned(),
        source: source as i32,
    })]))
}

/// The wire history and the new message as the turns the model seam carries,
/// bounded and attributed — or the `INVALID_ARGUMENT` that refuses the call.
///
/// Two different bounds, deliberately asymmetric. Length is a *bound*: an
/// over-long message or turn is refused, because trimming one mid-sentence
/// would have the coach answer something the person did not say. History depth
/// is a *truncation*: only the newest [`MAX_CHAT_TURNS`] are kept, silently,
/// because a transcript's length is the app's doing rather than the person's
/// and refusing them for it would answer nothing. Dropped turns are dropped
/// before validation — a malformed turn that no longer participates cannot
/// fail the request.
pub(super) fn conversation(
    history: Vec<pb::ChatTurn>,
    message: &str,
) -> Result<Vec<ChatTurn>, AssistantError> {
    let message = message.trim();
    if message.is_empty() {
        return Err(AssistantError::InvalidChat(
            "the message is empty".to_owned(),
        ));
    }
    if message.chars().count() > MAX_CHAT_MESSAGE_CHARS {
        return Err(AssistantError::InvalidChat(format!(
            "the message exceeds {MAX_CHAT_MESSAGE_CHARS} characters"
        )));
    }

    let newest = history.len().saturating_sub(MAX_CHAT_TURNS);
    let mut turns: Vec<ChatTurn> = history
        .into_iter()
        .skip(newest)
        .map(|turn| {
            if turn.text.chars().count() > MAX_CHAT_MESSAGE_CHARS {
                return Err(AssistantError::InvalidChat(format!(
                    "a history turn exceeds {MAX_CHAT_MESSAGE_CHARS} characters"
                )));
            }
            let role = match turn.role() {
                pb::ChatRole::Person => ChatRole::Person,
                pb::ChatRole::Coach => ChatRole::Coach,
                pb::ChatRole::Unspecified => {
                    return Err(AssistantError::InvalidChat(
                        "a history turn does not say who spoke".to_owned(),
                    ));
                }
            };
            Ok(ChatTurn {
                role,
                text: turn.text,
            })
        })
        .collect::<Result<_, _>>()?;

    turns.push(ChatTurn {
        role: ChatRole::Person,
        text: message.to_owned(),
    });
    Ok(turns)
}

/// [`model_chunks`] for the chat wire type.
pub(super) fn chat_from_model(chunks: ModelStream) -> ChatStream {
    model_chunks(chunks, "the reply stopped early", |text| pb::ChatResponse {
        text,
        source: pb::AssistantSource::Model as i32,
    })
}

/// Maps the model's chunks onto a wire type, one rule for every streaming RPC.
///
/// A chunk that fails mid-answer ends the stream rather than replacing what has
/// already been read: the person is looking at half an answer, and switching to
/// the fallback text at that point would contradict the sentence above it. It
/// ends with `UNAVAILABLE` rather than simply stopping, because a stream that
/// stops is indistinguishable from one that finished — the client would caption
/// a truncated answer as the whole of it. tonic ends the response at the first
/// `Err`, so nothing the provider sends after the failure can follow the status
/// onto the wire.
///
/// Generic over the wire constructor so the rule has one owner; `stopped` is
/// each RPC's own phrasing of it, logged and sent alike.
fn model_chunks<T>(
    chunks: ModelStream,
    stopped: &'static str,
    wire: impl Fn(String) -> T + Send + 'static,
) -> Pin<Box<dyn Stream<Item = Result<T, tonic::Status>> + Send>> {
    Box::pin(chunks.map(move |chunk| match chunk {
        Ok(text) => Ok(wire(text)),
        Err(error) => {
            tracing::warn!(feature = "assistant", %error, "{stopped}");
            Err(tonic::Status::unavailable(stopped))
        }
    }))
}

/// [`model_chunks`] for the explanation wire type.
pub(super) fn from_model(chunks: ModelStream) -> ExplanationStream {
    model_chunks(chunks, "the explanation stopped early", |text| {
        pb::ExplainTechniqueResponse {
            text,
            source: pb::AssistantSource::Model as i32,
        }
    })
}

/// Sends the rule-based explanation down the same pipe, a paragraph at a time,
/// flagged with why the model did not write it instead.
///
/// Chunked rather than sent whole so the client's accumulate-and-render path is
/// the one path — a fallback that arrived as a single message would leave the
/// streaming path exercised only when a model happens to be reachable.
///
/// The explanation's *text* is the same either way, unlike the chat's: a
/// technique's own notes are a real answer to "why does this work", so a caller
/// below Coach is being given something rather than being turned away. Only the
/// flag differs, which is what lets the client offer the subscription where
/// that is the reason and stay quiet where it is an outage.
pub(super) fn from_fallback(text: &str, source: pb::AssistantSource) -> ExplanationStream {
    let chunks: Vec<Result<pb::ExplainTechniqueResponse, tonic::Status>> = text
        .split_inclusive("\n\n")
        .map(|paragraph| {
            Ok(pb::ExplainTechniqueResponse {
                text: paragraph.to_owned(),
                source: source as i32,
            })
        })
        .collect();

    Box::pin(tokio_stream::iter(chunks))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wire_turn(role: pb::ChatRole, text: &str) -> pb::ChatTurn {
        pb::ChatTurn {
            role: role as i32,
            text: text.to_owned(),
        }
    }

    /// Truncation keeps the newest turns and always appends the message: the
    /// end of a conversation is what the next answer hangs on, and the person
    /// asked their question last.
    #[test]
    fn truncation_keeps_the_newest_turns_and_ends_on_the_message() {
        let history: Vec<pb::ChatTurn> = (0..MAX_CHAT_TURNS + 5)
            .map(|index| wire_turn(pb::ChatRole::Person, &format!("turn-{index}")))
            .collect();

        let turns = conversation(history, "the question").expect("a valid conversation");

        assert_eq!(turns.len(), MAX_CHAT_TURNS + 1, "history plus the message");
        assert_eq!(turns[0].text, "turn-5", "the oldest five are dropped");
        let last = turns.last().expect("the message is appended");
        assert_eq!(last.text, "the question");
        assert_eq!(last.role, ChatRole::Person);
    }

    /// The length rule is a bound, not a trim: the edge passes whole and one
    /// character past it refuses the call, for the message and for a history
    /// turn alike.
    #[test]
    fn the_character_bound_refuses_rather_than_trims() {
        let longest = "x".repeat(MAX_CHAT_MESSAGE_CHARS);
        let over = "x".repeat(MAX_CHAT_MESSAGE_CHARS + 1);

        assert!(conversation(Vec::new(), &longest).is_ok());
        assert!(matches!(
            conversation(Vec::new(), &over),
            Err(AssistantError::InvalidChat(_))
        ));
        assert!(matches!(
            conversation(vec![wire_turn(pb::ChatRole::Coach, &over)], "hello"),
            Err(AssistantError::InvalidChat(_))
        ));
    }

    /// An empty message — including one that is only whitespace — is a client
    /// bug, refused rather than answered with a reply to nothing.
    #[test]
    fn an_empty_message_is_refused() {
        assert!(matches!(
            conversation(Vec::new(), "   "),
            Err(AssistantError::InvalidChat(_))
        ));
    }

    /// A turn that does not name its speaker cannot be handed to the model as
    /// attributed speech, so it fails the request — unless truncation already
    /// dropped it, in which case it no longer participates and cannot.
    #[test]
    fn an_unattributed_turn_fails_only_while_it_participates() {
        assert!(matches!(
            conversation(
                vec![wire_turn(pb::ChatRole::Unspecified, "who said this")],
                "hello"
            ),
            Err(AssistantError::InvalidChat(_))
        ));

        let mut history = vec![wire_turn(pb::ChatRole::Unspecified, "who said this")];
        history.extend(
            (0..MAX_CHAT_TURNS).map(|index| wire_turn(pb::ChatRole::Person, &format!("{index}"))),
        );
        assert!(
            conversation(history, "hello").is_ok(),
            "a dropped turn cannot fail the request"
        );
    }
}
