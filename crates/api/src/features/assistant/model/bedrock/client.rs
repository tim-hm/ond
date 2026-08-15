//! The AWS SDK boundary for Bedrock calls.
//!
//! Client construction proves a credential source at boot, while each request
//! is bounded at the altitude appropriate to its shape: one timeout for a
//! complete response, and idle plus lifetime bounds for a stream. Provider
//! bodies and events are delegated to sibling modules so this file owns only
//! transport, cancellation, and the metadata safe to record.

use std::time::{Duration, Instant};

use aws_credential_types::provider::ProvideCredentials as _;
use aws_sdk_bedrockruntime::config::Region;
use aws_sdk_bedrockruntime::config::timeout::TimeoutConfig;
use aws_sdk_bedrockruntime::error::ProvideErrorMetadata as _;
use aws_sdk_bedrockruntime::operation::RequestId as _;
use aws_sdk_bedrockruntime::primitives::Blob;

use super::super::super::metrics;
use super::super::types::millis;
use super::super::{ModelClient, ModelError, ModelRequest, ModelStream};
use super::events::{Event, EventSource, STREAM_IDLE_TIMEOUT, parse_event, refused, relay_events};
use super::wire::{MessagesResponse, encode};
use crate::config;

/// Bounds a whole non-streaming call, retries included. Generous enough for a
/// long reply on a slow day and short enough that a hung provider does not hold
/// the person's screen: the breaker needs failures to arrive to be able to trip
/// on them.
///
/// Applied per request rather than on the client, because the streaming path
/// must not carry it — there the same ceiling would cut a healthy answer
/// mid-sentence at 45 seconds of perfectly good reading.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);

/// Bounds reaching Bedrock at all. A connection that has not been accepted is a
/// hang with nothing to wait for, on either path.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Bounds the credential lookup [`BedrockClient::connect`] does at boot.
///
/// On the box the chain ends at the instance metadata endpoint, which answers
/// in milliseconds when present — but "absent" can present as a hang rather
/// than a refusal on a network that blackholes the link-local address, and
/// startup must not depend on which. On a laptop it ends at a live STS
/// `AssumeRole` round trip (`ond-dev` is an assumed role), so the five seconds
/// also have a real network call to absorb.
const CREDENTIAL_PROBE_TIMEOUT: Duration = Duration::from_secs(5);

/// Chunks held between Bedrock's event stream and the client's.
///
/// Small: the point of streaming is that a chunk reaches the reader as it
/// arrives, and a deep buffer would let the decoder run ahead of a slow client
/// and hold the whole answer in memory instead.
const STREAM_BUFFER_FRAMES: usize = 16;

/// The production model client backed by Bedrock's Messages API.
///
/// Holds the SDK client rather than credentials. The SDK refreshes the instance
/// profile or assumed role underneath it, so a long-running process never
/// retains a credential past its lifetime.
pub struct BedrockClient {
    client: aws_sdk_bedrockruntime::Client,
}

impl BedrockClient {
    /// Builds a client, and proves this machine can sign for one.
    ///
    /// The proof is the point. Resolving credentials is otherwise lazy, so
    /// without this a laptop with no AWS identity would boot claiming the
    /// assistant is live and then fail every call until the breaker noticed —
    /// three wasted quota claims and a log line that lied. Failing here instead
    /// puts the process on the documented `DisabledModelClient` path, which is
    /// the same path a fresh clone and CI take.
    ///
    /// The credentials themselves are deliberately discarded: the SDK's own
    /// cache holds them and refreshes them before they expire, which an
    /// instance profile's six-hour lifetime requires and a copy kept here would
    /// not do.
    pub async fn connect() -> anyhow::Result<Self> {
        // rustls over ring, explicitly. The SDK's default HTTPS client selects
        // aws-lc-rs, which would put a second crypto backend in a binary that
        // already links ring through rustls for Postgres and Apple.
        let https = aws_smithy_http_client::Builder::new()
            .tls_provider(aws_smithy_http_client::tls::Provider::Rustls(
                aws_smithy_http_client::tls::rustls_provider::CryptoMode::Ring,
            ))
            .build_https();

        let sdk = aws_config::defaults(aws_config::BehaviorVersion::latest())
            .region(Region::new(config::BEDROCK_REGION))
            .http_client(https)
            .timeout_config(
                TimeoutConfig::builder()
                    .connect_timeout(CONNECT_TIMEOUT)
                    .read_timeout(STREAM_IDLE_TIMEOUT)
                    .build(),
            )
            // The default grace period cuts a response that delivers no bytes
            // for five seconds, which is a sane rule for an S3 download and
            // the wrong one for a model that can think before it speaks.
            // Stretched to the relay's idle timeout rather than switched off: once a
            // response has begun this is the only stall detector it has —
            // `read_timeout` no longer applies — and without it a provider
            // that accepts a stream and then goes quiet holds `events.recv()`,
            // and the person's screen, forever.
            .stalled_stream_protection(
                aws_sdk_bedrockruntime::config::StalledStreamProtectionConfig::enabled()
                    .grace_period(STREAM_IDLE_TIMEOUT)
                    .build(),
            )
            .load()
            .await;

        let provider = sdk
            .credentials_provider()
            .ok_or_else(|| anyhow::anyhow!("the AWS credential chain resolved to nothing"))?;

        tokio::time::timeout(CREDENTIAL_PROBE_TIMEOUT, provider.provide_credentials())
            .await
            .map_err(|_| {
                anyhow::anyhow!("the AWS credential chain did not answer within the probe timeout")
            })?
            .map_err(|error| anyhow::anyhow!("no AWS credentials are available: {error}"))?;

        Ok(Self {
            client: aws_sdk_bedrockruntime::Client::new(&sdk),
        })
    }
}

#[tonic::async_trait]
impl ModelClient for BedrockClient {
    async fn complete(&self, request: &ModelRequest) -> Result<String, ModelError> {
        let started = Instant::now();
        let body = encode(request)?;

        let response = self
            .client
            .invoke_model()
            .model_id(config::BEDROCK_MODEL_ID)
            .content_type("application/json")
            .accept("application/json")
            .body(Blob::new(body))
            .customize()
            // Every field restated rather than only the one being added: an
            // override layer replaces the base `TimeoutConfig` wholesale, so a
            // partial one would silently drop the connect and read bounds.
            .config_override(
                aws_sdk_bedrockruntime::Config::builder().timeout_config(
                    TimeoutConfig::builder()
                        .connect_timeout(CONNECT_TIMEOUT)
                        .read_timeout(STREAM_IDLE_TIMEOUT)
                        .operation_timeout(REQUEST_TIMEOUT)
                        .build(),
                ),
            )
            .send()
            .await
            .map_err(|error| {
                refused(
                    "the call did not complete",
                    error.code(),
                    error.request_id(),
                )
            })?;

        let reply: MessagesResponse = serde_json::from_slice(&response.body.into_inner())
            .map_err(|error| ModelError::Failed(format!("the reply did not decode: {error}")))?;

        // One line per paid call, before the content is judged — the call was
        // billed whatever the reply turns out to say. `info` survives the
        // million-requests test because the daily allowance bounds how many of
        // these a person can cause, and nothing else in the process records
        // what the assistant costs.
        let usage = reply.usage.as_ref();
        tracing::info!(
            feature = "assistant",
            model = config::BEDROCK_MODEL_ID,
            duration_ms = millis(started.elapsed()),
            prompt_tokens = usage.map(|usage| usage.input_tokens),
            completion_tokens = usage.map(|usage| usage.output_tokens),
            cached_tokens = usage.map(|usage| usage.cache_read_input_tokens),
            "the model answered"
        );

        // The same three numbers as a counter, beside the line that already
        // reports them. The line answers "what did this call cost" for somebody
        // reading the log on the box; the counter answers "what has the coach
        // cost this month", which no amount of reading a rotating file will.
        if let Some(usage) = usage {
            metrics::tokens(
                usage.input_tokens,
                usage.output_tokens,
                usage.cache_read_input_tokens,
            );
        }
        metrics::call_duration(started.elapsed());

        let text: String = reply
            .content
            .into_iter()
            .filter_map(|block| block.text)
            .collect();

        if text.trim().is_empty() {
            return Err(ModelError::Failed(
                "the reply carried no content".to_owned(),
            ));
        }
        Ok(text)
    }

    async fn stream(&self, request: &ModelRequest) -> Result<ModelStream, ModelError> {
        // Timed to the first chunk, which is the wait the reader experiences.
        // The relay separately bounds silence and total lifetime. No token
        // counts: they arrive on the closing frame, long after this line.
        let mut started = Some(Instant::now());
        let body = encode(request)?;

        let response = self
            .client
            .invoke_model_with_response_stream()
            .model_id(config::BEDROCK_MODEL_ID)
            .content_type("application/json")
            .accept("application/json")
            .body(Blob::new(body))
            .send()
            .await
            .map_err(|error| {
                refused(
                    "the call did not complete",
                    error.code(),
                    error.request_id(),
                )
            })?;

        // Captured before the body is moved: the event stream's own errors do
        // not carry it, and this is the id AWS knows the whole call by.
        let request_id = response.request_id().map(str::to_owned);

        let (sender, receiver) = tokio::sync::mpsc::channel(STREAM_BUFFER_FRAMES);
        let source = BedrockEventSource {
            response,
            request_id: request_id.clone(),
        };
        tokio::spawn(async move {
            relay_events(source, sender, started.take(), request_id.as_deref()).await;
        });

        Ok(Box::pin(tokio_stream::wrappers::ReceiverStream::new(
            receiver,
        )))
    }
}

struct BedrockEventSource {
    response: aws_sdk_bedrockruntime::operation::invoke_model_with_response_stream::InvokeModelWithResponseStreamOutput,
    request_id: Option<String>,
}

#[tonic::async_trait]
impl EventSource for BedrockEventSource {
    async fn next(&mut self) -> Result<Option<Event>, ModelError> {
        loop {
            let frame = self.response.body.recv().await.map_err(|error| {
                refused(
                    "the stream broke mid-answer",
                    error.code(),
                    self.request_id.as_deref(),
                )
            })?;
            let Some(frame) = frame else { return Ok(None) };
            let event = frame
                .as_chunk()
                .ok()
                .and_then(|chunk| chunk.bytes.as_ref())
                .map(Blob::as_ref)
                .map(parse_event);
            if let Some(event) = event {
                return Ok(Some(event));
            }
        }
    }
}
