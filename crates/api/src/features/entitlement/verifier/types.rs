//! What a verified transaction asserts, why one is refused, and the trait that
//! makes both answers.
//!
//! Split out of `mod.rs` so that opening the module still teaches its shape in a
//! screen — the rule `docs/code-structure.md` states and this seam had outgrown.

use chrono::{DateTime, Utc};

use super::super::types::SubscriptionTier;

/// Which App Store signed a transaction.
///
/// Apple signs Sandbox transactions with the same production certificate chain
/// as real ones, so the chain walk cannot separate them and this field is the
/// only thing that can. Without it a deployment cannot tell a free sandbox
/// subscription from a paid one, which is why it is read despite the standing
/// rule against carrying fields nothing acts on.
///
/// **Both are honoured, deliberately.** A `TestFlight` build points at the
/// production API — that is the whole point of testing against production — but
/// transacts in Sandbox. Refusing `Sandbox` here would leave every beta tester
/// unable to subscribe, which is the failure this field exists to prevent
/// rather than cause. So the environment is recorded and reported, not gated
/// on, and the boundary says so out loud when a sandbox purchase is honoured by
/// a production deployment.
///
/// The tightening path, once a beta window closes: refuse `Sandbox` when
/// [`crate::config::Environment::Production`] is in force. Doing that before
/// then trades a small, team-only abuse surface for a broken beta.
///
/// **That refusal belongs in [`TransactionVerifier::verify`], not in the
/// service.** The trait's own doc gives the rule — every check is inside it so
/// that "verified" means one thing — and a refusal written beside the log in
/// `submit_transaction` would be exactly the check a later caller forgets. It
/// sits on this type today only because nothing refuses anything yet: the field
/// is carried so the boundary can report, and the day it starts deciding,
/// `AppStoreVerifier` should take the expected environment at construction
/// (`main.rs` already holds `config.environment` there) and this field become
/// its output rather than its input.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreEnvironment {
    /// A real purchase, with money behind it.
    Production,

    /// A `TestFlight` or sandbox-tester purchase. Free, renews on an accelerated
    /// clock — a month is about five minutes — and creatable only by the team.
    Sandbox,

    /// Apple sent something this build does not recognise, or no `environment`
    /// at all.
    ///
    /// Its own variant rather than folding into [`Self::Sandbox`], and the
    /// distinction is the whole reason it exists. Folding would read as "we know
    /// this is sandbox" when the truth is "we could not tell" — and the moment
    /// the tightening lands, that lie refuses a genuine production purchase
    /// whose payload Apple has reshaped. Exactly the outcome reading this field
    /// was meant to prevent.
    ///
    /// So a tightening must refuse [`Self::Sandbox`] only, and treat this as
    /// production-or-unknown: entitle, and say so where somebody will see it.
    Unknown,
}

impl StoreEnvironment {
    /// Reads Apple's spelling, as it appears in the payload.
    ///
    /// Total rather than fallible: an unrecognised value is a real state this
    /// type represents, not an error the caller has to invent a policy for.
    ///
    /// `Xcode` is deliberately not a variant. A StoreKit-configuration
    /// transaction is signed by a per-machine certificate that never chains to
    /// Apple's root, so it is refused long before this is read; giving it a name
    /// here would imply a path that cannot happen.
    pub(super) fn parse(raw: Option<&str>) -> Self {
        match raw {
            Some("Production") => Self::Production,
            Some("Sandbox") => Self::Sandbox,
            _ => Self::Unknown,
        }
    }

    /// How this reads in a log line. Lowercase, because that is the register
    /// every other field value in this crate's events uses — Apple's
    /// capitalisation belongs on the wire, not in a log.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Production => "production",
            Self::Sandbox => "sandbox",
            Self::Unknown => "unknown",
        }
    }
}

/// What a signed transaction asserts, once its signature has been checked
/// against Apple's root and its app and product confirmed as ours.
///
/// Only the fields something acts on. The payload carries a dozen more —
/// purchase date, quantity, storefront, ownership type — and every one of them
/// would be a field to keep in step with a contract Apple owns.
///
/// `environment` is the exception that proves the rule. It earns its place
/// because Apple signs Sandbox transactions with the *same* production
/// certificate chain, so without reading it a deployment cannot tell a free
/// sandbox subscription from a paid one. It is carried rather than acted on:
/// see [`StoreEnvironment`] for why honouring both is deliberate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedTransaction {
    /// Which App Store signed this.
    ///
    /// Carried so the boundary can say so out loud. Nothing downstream branches
    /// on it — see [`StoreEnvironment`].
    pub environment: StoreEnvironment,

    /// The individual purchase or renewal Apple signed. A refund names this
    /// exact value, so it is the durable replay key.
    pub transaction_id: String,

    /// Stable across every renewal of one subscription, which is what makes a
    /// resubmission recognisable as belonging to the same subscription owner.
    pub original_transaction_id: String,

    /// Which product this is, resolved from the payload's `productId`. A
    /// `SubscriptionTier` rather than a `Tier` because a transaction is always
    /// a purchase — there is no free product to be a transaction for, and a
    /// `productId` naming neither of ours is rejected rather than mapped down.
    pub tier: SubscriptionTier,

    /// When this period ends. Not optional: an auto-renewable subscription
    /// always carries one, and a payload without it is not a transaction for a
    /// product this app sells — [`TransactionVerifier::verify`] rejects it
    /// rather than passing a `None` every caller would have to interpret.
    pub expires_at: DateTime<Utc>,

    /// When Apple signed this, which is what orders one submission against
    /// another.
    ///
    /// Carried out of the verifier because it is the only field that can order
    /// them correctly. The expiry cannot: upgrading Plus to Coach mid-month
    /// issues a Coach transaction whose expiry is *earlier* than the Plus period
    /// it replaced, so "keep the later expiry" would keep the subscription the
    /// person has just stopped paying for.
    pub signed_at: DateTime<Utc>,

    /// When Apple refunded or revoked it, if they did. `Some` means the
    /// transaction entitles nothing, however far in the future its expiry sits.
    pub revoked_at: Option<DateTime<Utc>>,
}

/// Why a submitted token bought nothing.
///
/// Three variants because they mean three different things about the caller —
/// a client bug, an attack, and a build pointed at the wrong app — and the
/// message travels to the client, so the distinction is what a developer sees
/// when a submission fails.
#[derive(Debug, thiserror::Error)]
pub enum VerificationError {
    /// Not a JWS at all, or a JWS whose parts do not decode: wrong segment
    /// count, invalid base64url, a header or payload that is not the JSON this
    /// expects.
    #[error("the signed transaction is malformed: {0}")]
    Malformed(String),

    /// The bytes parsed, and the signature does not lead back to Apple's root
    /// certificate. Also covers a chain that is well-formed but expired, and an
    /// algorithm other than the ES256 Apple signs with.
    #[error("the signed transaction is not signed by Apple: {0}")]
    Untrusted(String),

    /// Genuinely Apple's, and for somebody else's app or a product this build
    /// does not sell. The one rejection that is not a bug on either side: a
    /// development build with the wrong bundle id produces exactly this, and so
    /// does an old client still submitting a product that has been withdrawn.
    #[error("the signed transaction is not for this app: {0}")]
    NotOurs(String),
}

/// What the entitlement feature needs from a signature checker, and nothing
/// else.
///
/// A plain `trait` used through `dyn`, matching `assistant::model::ModelClient`:
/// the composition root picks the implementation at startup, and the service is
/// written against the trait so no test can reach a real certificate chain by
/// accident.
pub trait TransactionVerifier: Send + Sync {
    /// Checks `signed_transaction` and returns what it asserts.
    ///
    /// Every check is in here rather than split with the caller, because
    /// "verified" has to mean one thing: the signature leads to Apple's root,
    /// the app is this app, and the product is the one this app sells. A
    /// service that had to remember to check the bundle id afterwards would
    /// eventually forget.
    fn verify(&self, signed_transaction: &str) -> Result<VerifiedTransaction, VerificationError>;
}

/// Folds a take-apart failure into the malformed arm.
impl From<crate::jws::MalformedJws> for VerificationError {
    fn from(error: crate::jws::MalformedJws) -> Self {
        Self::Malformed(error.0)
    }
}
