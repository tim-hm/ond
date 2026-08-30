//! What one caller may spend, and the two budgets that bound it. Nothing in
//! front of this process rations anything — stock `caddy:2` has no rate
//! limiter — so the ration ships with the binary it protects. Two budgets
//! because the threats grow at different rates: requests bound board work; new
//! identities bound `users` rows, each carrying its own assistant allowance and Bedrock spend.

use std::collections::hash_map::RandomState;
use std::hash::BuildHasher;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::extract::{Request, State};
use axum::http::HeaderMap;
use axum::middleware::Next;
use axum::response::Response;
use std::sync::Arc;
use tonic::Status;

use crate::state::AppState;

/// The header naming who is really calling. Caddy *appends* the peer it
/// accepted the connection from, so a caller who sends a value of their own
/// keeps it — as the left-most entry. Only the right-most one was written by
/// something we run, which is why [`client_key`] reads from that end and no other.
pub const FORWARDED_FOR: &str = "x-forwarded-for";

/// How long a budget's allowance lasts before it refills.
const WINDOW: Duration = Duration::from_mins(1);

/// Requests per [`WINDOW`], per caller — far above what the app asks for and
/// far below what a script achieves. Ten a second leaves an order of
/// magnitude of headroom for carrier-grade NAT, where one address fronts many
/// strangers, while cutting a fresh-UUID loop by three orders of magnitude.
/// It bounds the worst case, not the normal one.
pub const REQUESTS_PER_WINDOW: u32 = 600;

/// New `users` rows per [`WINDOW`], per caller — three orders of magnitude
/// tighter than the request budget, because a real client creates exactly one
/// identity, ever. Ten a minute tolerates a NAT full of installers and a
/// reinstall loop while capping what one address can add to a 10 GiB volume.
/// Charged only when a row is genuinely created, so no established client is ever refused by it.
pub const NEW_IDENTITIES_PER_WINDOW: u32 = 10;

/// How many counters each budget keeps. A fixed table rather than a map keyed
/// by caller, because a map keyed by whatever an attacker puts in a header is
/// one more thing they can grow without bound — the memory would become the
/// attack. The cost is that two callers can share a counter; see [`Budget`].
const SLOTS: u64 = 4096;

/// How the two halves of a slot are packed. The spend occupies the low bits and
/// the window the high ones, so both move in one atomic write — kept apart, a
/// rollover could land between another request's read and write and reset a
/// counter that had just been spent.
const SPEND_BITS: u32 = 32;
const SPEND_MASK: u64 = (1 << SPEND_BITS) - 1;

/// A caller's allowance, counted in fixed windows over a fixed-size table.
/// Callers hash into [`SLOTS`] counters: a collision makes the limit stricter
/// for two callers, never absent for one, and per-process `RandomState` means
/// collisions cannot be aimed at somebody. Fixed windows admit up to twice the
/// limit across a boundary — noise for an abuse control, bought with one atomic per request.
struct Budget {
    slots: Box<[AtomicU64]>,
    hasher: RandomState,
    limit: u64,

    /// Which budget this is, for the one line [`Budget::spend`] writes. The two
    /// are refused with a deliberately indistinguishable status — see
    /// [`refused`] — but that is a rule about what the *caller* learns, and a
    /// reader of the log who cannot tell a request flood from an identity flood
    /// cannot tell which control did the work.
    name: &'static str,
}

impl Budget {
    fn new(name: &'static str, limit: u32) -> Self {
        Self {
            slots: (0..SLOTS).map(|_| AtomicU64::new(0)).collect(),
            hasher: RandomState::new(),
            limit: u64::from(limit),
            name,
        }
    }

    /// Charges one unit to `key`, reporting whether it was within budget. A
    /// refusal costs nothing further: the counter is never incremented past
    /// the limit. The fill line is written where the slot reaches the limit —
    /// once per window per caller — and the refusals that follow repeat the
    /// same fact at the attacker's chosen rate, so they log at `debug`.
    fn spend(&self, key: &str, now: Duration) -> bool {
        // Masked rather than merely divided, so the shift below cannot push
        // bits off the top. At a one-minute window the mask is reached after
        // about eight thousand years, and a caller alive on that boundary gets
        // one extra allowance.
        let window = (now.as_secs() / WINDOW.as_secs()) & SPEND_MASK;

        // `% SLOTS` in the u64 domain, so the index is provably below 4096 and
        // needs no fallible narrowing.
        let index = usize::try_from(self.hasher.hash_one(key) % SLOTS).unwrap_or(0);
        let slot = &self.slots[index];

        let mut packed = slot.load(Ordering::Relaxed);
        loop {
            let spent = if packed >> SPEND_BITS == window {
                packed & SPEND_MASK
            } else {
                0
            };

            if spent >= self.limit {
                return false;
            }

            let next = (window << SPEND_BITS) | (spent + 1);
            match slot.compare_exchange_weak(packed, next, Ordering::Relaxed, Ordering::Relaxed) {
                Ok(_) => {
                    // The write that fills the budget — only one request per
                    // window can be, since every later attempt is refused
                    // above. `warn` because it names which budget filled, and
                    // status 8 cannot: a carrier NAT spending the request
                    // budget and a script spending the identity budget differ.
                    if spent + 1 == self.limit {
                        tracing::warn!(
                            budget = self.name,
                            "a caller has spent their whole budget for this window"
                        );
                    }

                    return true;
                }
                // Another request touched this slot first; re-read and retry
                // against what it left.
                Err(current) => packed = current,
            }
        }
    }
}

/// Where a [`Throttle`] reads the time its windows are cut from.
///
/// A bare `fn` rather than a trait object or a generic: neither implementation
/// captures anything, so the request path pays nothing for the indirection and
/// nothing here has to name a lifetime.
pub type Clock = fn() -> Duration;

/// Both budgets, held for the life of the process. Lives on `AppState` rather
/// than being injected: the counters are not a seam — nothing outside this
/// crate chooses an implementation, and what a test wants is the behaviour
/// through the router. Its *clock* is the one exception; [`Throttle::with_clock`] says why.
pub struct Throttle {
    requests: Budget,
    new_identities: Budget,
    clock: Clock,
}

impl Throttle {
    pub fn new() -> Self {
        Self::with_clock(since_epoch)
    }

    /// The same budgets, counted against a clock the caller chooses — for
    /// `tests/e2e/throttle.rs` and nothing else. A burst of several hundred
    /// real requests crosses a minute boundary about one run in seven, and the
    /// refill serves the caller twice their budget — [`Budget`]'s documented
    /// behaviour — so the test stops the clock and asserts the budget, not the wall time.
    pub fn with_clock(clock: Clock) -> Self {
        Self {
            requests: Budget::new("requests", REQUESTS_PER_WINDOW),
            new_identities: Budget::new("new-identities", NEW_IDENTITIES_PER_WINDOW),
            clock,
        }
    }

    /// Whether `key` may make one more request this window.
    fn spend_request(&self, key: &str) -> bool {
        self.requests.spend(key, (self.clock)())
    }

    /// Whether `key` may bring one more `users` row into existence this window.
    pub fn spend_new_identity(&self, key: &str) -> bool {
        self.new_identities.spend(key, (self.clock)())
    }
}

/// The one answer a caller over either budget gets. Shared by the two call
/// sites so the client cannot learn which limit it met: telling somebody
/// probing for identities that they hit the *identity* budget tells them the
/// request budget is still open and worth switching to.
pub fn refused() -> Response {
    Status::resource_exhausted("rate limit exceeded").into_http()
}

impl Default for Throttle {
    fn default() -> Self {
        Self::new()
    }
}

/// A clock that cannot go backwards into a panic.
///
/// `SystemTime` before the epoch is not reachable on a machine that can reach
/// Postgres, and the alternative — an `Instant` baseline — would mean storing
/// one and subtracting on every request to compute the same number.
fn since_epoch() -> Duration {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
}

/// What to charge a request to: the right-most `X-Forwarded-For` entry, the
/// one Caddy wrote — see [`FORWARDED_FOR`]. The absent case is deliberately
/// not an exemption: no header means nothing we run proxied this, which on the
/// box cannot come from the internet, so such requests share one budget — the
/// day something *is* exposed directly, the limit is coarse instead of silently absent.
pub fn client_key(headers: &HeaderMap) -> &str {
    const DIRECT: &str = "direct";

    headers
        .get(FORWARDED_FOR)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.rsplit(',').next())
        .map_or(DIRECT, str::trim)
}

/// Refuses a caller who has spent their request budget. Inside `GrpcWebLayer`
/// so the refusal leaves as a gRPC-Web status the client can read, and outside
/// `identity::resolve` so a refused request never reaches the database at all
/// — including the upsert that is the reason the second budget exists.
pub async fn enforce(State(state): State<Arc<AppState>>, request: Request, next: Next) -> Response {
    if !state.throttle.spend_request(client_key(request.headers())) {
        // The key is not logged — it is somebody's IP address, and
        // `web/privacy.html` does not say this service keeps one. `debug`
        // rather than `warn`: one line per refused request, and the throttle
        // exists for callers making thousands a second. `Budget::spend` writes
        // the `warn` where a budget fills.
        tracing::debug!("refused a request over its rate limit");
        return refused();
    }

    next.run(request).await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A budget under any name. Which one it is decides only what the line
    /// `Budget::spend` writes says, and no test here reads that.
    fn budget(limit: u32) -> Budget {
        Budget::new("requests", limit)
    }

    fn headers_with(forwarded_for: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(FORWARDED_FOR, forwarded_for.parse().expect("a valid value"));
        headers
    }

    /// The whole reason the right-hand end is read: a caller who forges the
    /// header keeps their forgery, and Caddy's entry lands after it. Reading
    /// from the left would let one attacker present a fresh identity per
    /// request and never meet either budget.
    #[test]
    fn a_forged_prefix_does_not_change_the_key() {
        assert_eq!(
            client_key(&headers_with("9.9.9.9, 203.0.113.7")),
            "203.0.113.7"
        );
        assert_eq!(client_key(&headers_with("203.0.113.7")), "203.0.113.7");
    }

    /// An unproxied request is charged, not waved through — see [`client_key`].
    #[test]
    fn a_request_with_no_forwarded_header_still_has_a_key() {
        assert!(!client_key(&HeaderMap::new()).is_empty());
    }

    #[test]
    fn a_budget_admits_its_limit_and_then_refuses() {
        let budget = budget(3);
        let now = Duration::from_secs(0);

        assert!((0..3).all(|_| budget.spend("caller", now)));
        assert!(!budget.spend("caller", now));
    }

    /// Callers are counted apart, which is what makes the limit a limit on an
    /// attacker rather than on everybody at once.
    #[test]
    fn one_caller_exhausting_a_budget_leaves_another_untouched() {
        let budget = budget(1);
        let now = Duration::from_secs(0);

        assert!(budget.spend("noisy", now));
        assert!(!budget.spend("noisy", now));
        assert!(budget.spend("quiet", now));
    }

    /// The allowance refills. Asserted by moving the clock rather than by
    /// sleeping, which is the only reason `spend` takes the time as an argument.
    #[test]
    fn a_new_window_refills_the_allowance() {
        let budget = budget(1);

        assert!(budget.spend("caller", Duration::from_secs(0)));
        assert!(!budget.spend("caller", Duration::from_secs(59)));
        assert!(budget.spend("caller", WINDOW));
    }
}
