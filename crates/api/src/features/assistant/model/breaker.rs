//! Stops calling a model that keeps failing.
//!
//! A decorator rather than a check inside the service: the service already
//! handles "the model did not answer" by falling back, so a breaker that
//! answers `Unavailable` needs no new branch anywhere. It also means the
//! breaker wraps the scripted test double exactly as it wraps the real client,
//! which is how the trip-and-recover behaviour is testable at all.
//!
//! In-process and per-instance. One box serves this app, so a shared breaker
//! would be a Redis dependency bought to coordinate a single process with
//! itself; when there are two boxes, the worst case is each discovering the
//! outage separately.

use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::Poll;
use std::time::{Duration, Instant};

use tokio_stream::Stream;

use super::types::millis;
use super::{AssistantMode, ModelChunk, ModelClient, ModelError, ModelRequest, ModelStream};

/// Consecutive failures that trip it.
///
/// Consecutive, not a rate: a single timeout is weather, and three in a row
/// with no success between them is the provider being down. Low enough that a
/// real outage costs a handful of slow requests rather than every request for
/// the length of it.
const FAILURES_TO_TRIP: u32 = 3;

/// How long it stays open before letting one call through.
const COOLDOWN: Duration = Duration::from_mins(1);

/// A [`ModelClient`] that refuses to call a model which has just failed
/// repeatedly.
pub struct GuardedModelClient {
    inner: Arc<dyn ModelClient>,
    recorder: Recorder,
}

/// The breaker's shared half: the policy and the state it folds outcomes into.
///
/// Split out of [`GuardedModelClient`] so a returned stream can carry a clone
/// and record its outcome when that outcome actually exists — a stream's
/// establishment says the provider picked up, not that it answered.
#[derive(Clone)]
struct Recorder {
    failures_to_trip: u32,
    cooldown: Duration,
    // `std::sync::Mutex`, held only for the handful of statements that read or
    // write the counter — never across an await, which is what
    // `clippy::await_holding_lock` exists to catch.
    state: Arc<Mutex<State>>,
}

/// The counter, when the breaker last gave up, and whether the provider has
/// ever answered.
#[derive(Default)]
struct State {
    consecutive_failures: u32,
    /// `Some` while open. Cleared by the first call let through, whatever its
    /// outcome — a half-open probe that failed re-opens by tripping again.
    open_until: Option<Instant>,
    /// Set by the first call that succeeds, and never cleared.
    ///
    /// Not the breaker's own business, but the breaker is the one place every
    /// call's outcome already passes through, and a second decorator to hold
    /// one bool would be machinery bought for nothing. What it buys is that
    /// `/about` can report evidence instead of intent: credentials that resolve
    /// are not credentials that are *authorised*, so a deployment whose role
    /// carries no `bedrock:InvokeModel` grant installs a provider client and
    /// looks live from outside until something asks it for a reply. Until this
    /// is set, nothing has.
    answered: bool,
}

impl GuardedModelClient {
    pub fn new(inner: Arc<dyn ModelClient>) -> Self {
        Self::with_policy(inner, FAILURES_TO_TRIP, COOLDOWN)
    }

    /// The same guard with an explicit policy, so a test can trip and recover it
    /// inside one test rather than waiting out the real cooldown.
    pub fn with_policy(
        inner: Arc<dyn ModelClient>,
        failures_to_trip: u32,
        cooldown: Duration,
    ) -> Self {
        Self {
            inner,
            recorder: Recorder {
                failures_to_trip,
                cooldown,
                state: Arc::new(Mutex::new(State::default())),
            },
        }
    }

    /// Whether this call may proceed, clearing an expired cooldown on the way
    /// past.
    ///
    /// The two transitions are logged here and in [`Self::record`] rather than
    /// in the service: the caller asks `is_available()` before it prepares
    /// anything, so an open breaker never reaches a `warn` up there and a whole
    /// cooldown of degraded answers would otherwise pass without a line. Both
    /// are per outage rather than per request — only an admitted call can trip
    /// it, and only the first call past the cooldown closes it. Near enough,
    /// anyway: streams admitted before a trip settle their outcomes after it,
    /// and each late failure past the threshold re-arms the cooldown and its
    /// warn — a heuristic's wart, not a lie worth machinery.
    fn admits(&self) -> bool {
        let Ok(mut state) = self.recorder.state.lock() else {
            // A poisoned lock means a previous holder panicked mid-update. The
            // counter is a heuristic, so failing calls closed over it would
            // trade a recoverable inaccuracy for an outage.
            return true;
        };

        match state.open_until {
            Some(until) if Instant::now() < until => false,
            Some(_) => {
                state.open_until = None;
                state.consecutive_failures = 0;
                tracing::info!(
                    feature = "assistant",
                    "the model breaker closed; trying the provider again"
                );
                true
            }
            None => true,
        }
    }

    /// Whether the breaker is open right now, without touching the counter.
    ///
    /// Separate from [`Self::admits`], which clears an expired cooldown as it
    /// passes: this one is asked speculatively, before a call is prepared, and a
    /// peek that reset the breaker would let a caller who then decided not to
    /// call consume the one probe the cooldown allows.
    fn is_open(&self) -> bool {
        self.recorder
            .state
            .lock()
            .ok()
            .and_then(|state| state.open_until)
            .is_some_and(|until| Instant::now() < until)
    }

    /// Whether the provider has answered at least once since this process
    /// started. A poisoned lock reads as "not yet", which understates rather
    /// than overstates — the one direction this field must never fail in.
    fn has_answered(&self) -> bool {
        self.recorder.state.lock().is_ok_and(|state| state.answered)
    }

    fn refusal() -> ModelError {
        ModelError::unavailable("recent calls failed; waiting before trying again")
    }
}

impl Recorder {
    /// Folds one attempt's outcome into the counter.
    fn record(&self, succeeded: bool) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };

        if succeeded {
            state.consecutive_failures = 0;
            state.answered = true;
            return;
        }

        state.consecutive_failures += 1;
        if state.consecutive_failures >= self.failures_to_trip {
            state.open_until = Some(Instant::now() + self.cooldown);
            tracing::warn!(
                feature = "assistant",
                consecutive_failures = state.consecutive_failures,
                cooldown_ms = millis(self.cooldown),
                "the model breaker opened; answering from the rules"
            );
        }
    }
}

/// Carries a stream's eventual outcome back to the breaker.
///
/// A terminal error — a stalled provider surfaced by the stall detector, a
/// broken frame — counts as the failure it is; a stream that ends cleanly
/// counts as the answer. A stream dropped mid-answer records nothing: the
/// person walked away, which proves nothing about the provider either way.
struct RecordedStream {
    inner: ModelStream,
    recorder: Recorder,
    /// Whether the outcome has been folded in, so a decoder that yields an
    /// error and then more frames cannot count one stream twice.
    settled: bool,
}

impl Stream for RecordedStream {
    type Item = Result<ModelChunk, ModelError>;

    fn poll_next(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        let next = this.inner.as_mut().poll_next(cx);

        match &next {
            Poll::Ready(Some(Err(_))) if !this.settled => {
                this.settled = true;
                this.recorder.record(false);
            }
            Poll::Ready(None) if !this.settled => {
                this.settled = true;
                this.recorder.record(true);
            }
            _ => {}
        }

        next
    }
}

#[tonic::async_trait]
impl ModelClient for GuardedModelClient {
    async fn complete(&self, request: &ModelRequest) -> Result<String, ModelError> {
        if !self.admits() {
            return Err(Self::refusal());
        }

        let result = self.inner.complete(request).await;
        self.recorder.record(result.is_ok());
        result
    }

    /// Establishment settles nothing: an outcome is recorded when the stream
    /// fails or finishes, not when the provider picks up.
    ///
    /// This used to count establishment alone, on the argument that a failure
    /// after the first chunk cannot be retried anyway — true, and beside the
    /// point: recording is not retrying. The stall detector turns provider
    /// silence into exactly such mid-stream failures, so a provider that
    /// accepts every stream and then stalls it was resetting the counter on
    /// each pickup and burning a quota claim per 30-second stall, indefinitely,
    /// with the breaker never opening (TIM-124).
    async fn stream(&self, request: &ModelRequest) -> Result<ModelStream, ModelError> {
        if !self.admits() {
            return Err(Self::refusal());
        }

        match self.inner.stream(request).await {
            Err(error) => {
                self.recorder.record(false);
                Err(error)
            }
            Ok(stream) => Ok(Box::pin(RecordedStream {
                inner: stream,
                recorder: self.recorder.clone(),
                settled: false,
            })),
        }
    }

    /// The only place [`AssistantMode::Live`] is ever produced, because this is
    /// the only implementation that sees how calls turn out.
    ///
    /// The promotion is one-way and earned: an installed model reports
    /// [`AssistantMode::Untried`] until a call has actually succeeded. An open
    /// breaker reads as [`AssistantMode::Interrupted`] — weather, not a
    /// deployment that cannot reach the provider at all — and a wrapped client
    /// that declines outright passes through unchanged, since only a client
    /// that is trying can be untried.
    fn mode(&self) -> AssistantMode {
        if self.is_open() {
            return AssistantMode::Interrupted;
        }

        match self.inner.mode() {
            AssistantMode::Untried if self.has_answered() => AssistantMode::Live,
            mode => mode,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fmt::Debug;

    use tracing::field::{Field, Visit};
    use tracing_subscriber::layer::{Context, Layer, SubscriberExt as _};

    use super::*;

    /// A provider that is down.
    struct AlwaysFails;

    #[tonic::async_trait]
    impl ModelClient for AlwaysFails {
        async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
            Err(ModelError::Failed("down".to_owned()))
        }

        async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
            Err(ModelError::Failed("down".to_owned()))
        }
    }

    /// A provider that answers.
    struct AlwaysAnswers;

    #[tonic::async_trait]
    impl ModelClient for AlwaysAnswers {
        async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
            Ok("up".to_owned())
        }

        async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
            Ok(Box::pin(tokio_stream::iter([Ok(
                super::super::ModelChunk::Text("up".to_owned()),
            )])))
        }
    }

    /// The smallest request the breaker will carry; none of these tests read it.
    fn request() -> ModelRequest {
        ModelRequest {
            cacheable_prefix: String::new(),
            instruction: String::new(),
            turns: Vec::new(),
            tools: Vec::new(),
            max_tokens: 1,
        }
    }

    /// Every event's message, which is the whole of what these assertions need.
    #[derive(Clone, Default)]
    struct Captured(Arc<Mutex<Vec<String>>>);

    impl<S: tracing::Subscriber> Layer<S> for Captured {
        fn on_event(&self, event: &tracing::Event<'_>, _context: Context<'_, S>) {
            let mut messages = self.0.lock().expect("the capture is not poisoned");
            event.record(&mut Message(&mut messages));
        }
    }

    struct Message<'a>(&'a mut Vec<String>);

    impl Visit for Message<'_> {
        fn record_debug(&mut self, field: &Field, value: &dyn Debug) {
            if field.name() == "message" {
                self.0.push(format!("{value:?}"));
            }
        }
    }

    /// The outage has to leave a record. The service asks `is_available()`
    /// before it prepares anything, so while the breaker is open no call reaches
    /// a log site above it — without these two lines a cooldown of degraded
    /// answers is indistinguishable from a quiet minute.
    #[tokio::test]
    async fn both_transitions_are_logged() {
        let captured = Captured::default();
        let guard =
            tracing::subscriber::set_default(tracing_subscriber::registry().with(captured.clone()));

        let breaker =
            GuardedModelClient::with_policy(Arc::new(AlwaysFails), 2, Duration::from_millis(50));
        let request = request();

        for _ in 0..2 {
            drop(breaker.complete(&request).await);
        }
        assert_eq!(
            breaker.mode(),
            AssistantMode::Interrupted,
            "two failures trip this policy, and an open breaker reads as weather"
        );

        tokio::time::sleep(Duration::from_millis(60)).await;
        drop(breaker.complete(&request).await);

        drop(guard);
        let messages = captured
            .0
            .lock()
            .expect("the capture is not poisoned")
            .clone();
        assert!(
            messages.iter().any(|line| line.contains("breaker opened")),
            "the trip is recorded: {messages:?}"
        );
        assert!(
            messages.iter().any(|line| line.contains("breaker closed")),
            "the recovery is recorded: {messages:?}"
        );
    }

    /// A model that is installed is not a model that works, and `/about` must
    /// not conflate them.
    ///
    /// This is the failure that hid an unapplied IAM policy: the box's
    /// credentials resolved, so the provider client installed and the process
    /// looked live from outside, while the role carried no `bedrock:InvokeModel`
    /// grant and every call would have come back `AccessDenied`. Nobody asked it
    /// anything, so nothing disproved it. Only an answer promotes `Untried` to
    /// `Live` — a call that failed proves nothing, and neither does a client
    /// nobody has called.
    #[tokio::test]
    async fn only_an_answer_makes_the_model_live() {
        let answering = GuardedModelClient::new(Arc::new(AlwaysAnswers));
        assert_eq!(answering.mode(), AssistantMode::Untried);
        assert!(
            answering.is_available(),
            "untried is unproven, not unavailable — the call has to be tried to prove it"
        );

        answering
            .complete(&request())
            .await
            .expect("this provider answers");
        assert_eq!(answering.mode(), AssistantMode::Live);

        let failing = GuardedModelClient::new(Arc::new(AlwaysFails));
        drop(failing.complete(&request()).await);
        assert_eq!(
            failing.mode(),
            AssistantMode::Untried,
            "a call that failed is not an answer"
        );
    }

    /// The outage TIM-124 names: a provider that picks up every stream and then
    /// stalls it. Establishment-only counting reset the counter on each pickup,
    /// so the breaker never opened and every caller burned a quota claim on a
    /// 30-second stall.
    struct EstablishesThenStalls;

    #[tonic::async_trait]
    impl ModelClient for EstablishesThenStalls {
        async fn complete(&self, _request: &ModelRequest) -> Result<String, ModelError> {
            Err(ModelError::Failed("down".to_owned()))
        }

        async fn stream(&self, _request: &ModelRequest) -> Result<ModelStream, ModelError> {
            Ok(Box::pin(tokio_stream::iter([Err(ModelError::Failed(
                "the provider went quiet mid-stream".to_owned(),
            ))])))
        }
    }

    #[tokio::test]
    async fn stalled_streams_trip_the_breaker() {
        use tokio_stream::StreamExt as _;

        let breaker = GuardedModelClient::with_policy(Arc::new(EstablishesThenStalls), 2, COOLDOWN);
        let request = request();

        for _ in 0..2 {
            let mut stream = breaker
                .stream(&request)
                .await
                .expect("this provider always picks up");
            while stream.next().await.is_some() {}
        }

        assert_eq!(
            breaker.mode(),
            AssistantMode::Interrupted,
            "two stalled streams are two failures, however politely they began"
        );
    }

    /// The stream-side half of the promotion rule: picking up is not answering.
    #[tokio::test]
    async fn only_a_finished_stream_is_an_answer() {
        use tokio_stream::StreamExt as _;

        let breaker = GuardedModelClient::new(Arc::new(AlwaysAnswers));
        let request = request();

        let mut stream = breaker
            .stream(&request)
            .await
            .expect("this provider answers");
        assert_eq!(
            breaker.mode(),
            AssistantMode::Untried,
            "an established stream has proven the provider picks up, not that it answers"
        );

        while stream.next().await.is_some() {}
        assert_eq!(breaker.mode(), AssistantMode::Live);
    }
}
