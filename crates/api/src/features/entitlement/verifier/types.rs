//! What a verified transaction asserts, why one is refused, and the trait that
//! makes both answers.

use chrono::{DateTime, Utc};

use super::super::types::SubscriptionTier;

/// Which App Store signed a transaction. Apple signs Sandbox transactions with
/// the same production chain, so this field is the only thing that separates
/// them. Both are honoured, deliberately, and nothing gates on it. The reason,
/// and the tightening path that would refuse `Sandbox` in production, are in
/// docs/architecture.md, "App Store entitlement verification".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreEnvironment {
    /// A real purchase, with money behind it.
    Production,

    /// A `TestFlight` or sandbox-tester purchase. Free, renews on an accelerated
    /// clock — a month is about five minutes — and creatable only by the team.
    Sandbox,

    /// Apple sent something this build does not recognise, or no `environment`
    /// at all. Its own variant rather than folded into [`Self::Sandbox`]: folding would
    /// read as "we know this is sandbox" when the truth is "we could not tell".
    /// A tightening must refuse [`Self::Sandbox`] only, and treat this as
    /// production-or-unknown — entitle, and say so where somebody will see it.
    Unknown,
}

impl StoreEnvironment {
    /// Reads Apple's spelling, as it appears in the payload. Total rather than
    /// fallible: an unrecognised value is a real state, not an error. `Xcode` is
    /// deliberately not a variant — a StoreKit-configuration transaction never
    /// chains to Apple's root, so it is refused long before this is read.
    pub(super) fn parse(raw: Option<&str>) -> Self {
        match raw {
            Some("Production") => Self::Production,
            Some("Sandbox") => Self::Sandbox,
            _ => Self::Unknown,
        }
    }

    /// How this reads in a log line. Lowercase, matching every other field value
    /// in this crate's events; Apple's capitalisation belongs on the wire.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Production => "production",
            Self::Sandbox => "sandbox",
            Self::Unknown => "unknown",
        }
    }
}

/// What a signed transaction asserts, once its signature has been checked
/// against Apple's root and its app and product confirmed as ours. Only the
/// fields something acts on: the payload carries a dozen more, each of which
/// would be a field to keep in step with a contract Apple owns. `environment` is
/// the exception — see [`StoreEnvironment`].
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
    /// another. The expiry cannot: moving from the yearly önd+ cadence to
    /// monthly issues a transaction whose expiry is *earlier* than the year it
    /// replaces, so "keep the later expiry" would keep the period the person has
    /// just stopped paying for.
    pub signed_at: DateTime<Utc>,

    /// When Apple refunded or revoked it, if they did. `Some` means the
    /// transaction entitles nothing, however far in the future its expiry sits.
    pub revoked_at: Option<DateTime<Utc>>,
}

/// Why a submitted token bought nothing. Three variants because they mean three
/// different things about the caller: a client bug, an attack, and a build
/// pointed at the wrong app. The message travels to the client, so the
/// distinction is what a developer sees when a submission fails.
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
    /// development build with the wrong bundle id produces it, and so does an
    /// old client submitting a withdrawn product.
    #[error("the signed transaction is not for this app: {0}")]
    NotOurs(String),
}

impl VerificationError {
    /// Which kind of rejection this is, as a metric label. The variant name and
    /// never the message: the variants are a closed set, while each `String`
    /// names a certificate or a parse position, and in Loki an unbounded label
    /// value is a stream per value. This is what makes `PurchasesBeingRejected`
    /// diagnosable without raising a log level on a live box.
    pub const fn kind(&self) -> &'static str {
        match self {
            Self::Malformed(_) => "malformed",
            Self::Untrusted(_) => "untrusted",
            Self::NotOurs(_) => "not_ours",
        }
    }
}

/// What the entitlement feature needs from a signature checker, and nothing
/// else. A plain `trait` used through `dyn`, matching
/// `assistant::model::ModelClient`: the composition root picks the
/// implementation at startup, and no test can reach a real chain by accident.
pub trait TransactionVerifier: Send + Sync {
    /// Checks `signed_transaction` and returns what it asserts. Every check is
    /// in here rather than split with the caller, so that "verified" means one
    /// thing: the signature leads to Apple's root, the app is this app, and the
    /// product is one this app sells.
    fn verify(&self, signed_transaction: &str) -> Result<VerifiedTransaction, VerificationError>;
}

/// Folds a take-apart failure into the malformed arm.
impl From<crate::jws::MalformedJws> for VerificationError {
    fn from(error: crate::jws::MalformedJws) -> Self {
        Self::Malformed(error.0)
    }
}
