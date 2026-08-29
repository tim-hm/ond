//! Sign-in outcomes. One counter, because a first-ever sign-in used to write
//! nothing: merges log (destructive), and `ond_users_total` counts anonymous
//! identities whether or not anybody signs in, so neither could answer "did
//! anybody create an account today". A counter, not a log line, because this
//! is a rate (docs/observability.md).

use metrics::counter;

/// What a sign-in did to the caller's identity.
///
/// Named outcomes rather than inferred ones: comparing the adopted id to the
/// caller separates a merge from the rest but cannot tell a new person from a
/// returning one — the pair launch week most needs apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignIn {
    /// Nobody held this Apple account: the caller now does. A new subscriber's
    /// first sign-in, and the number launch week actually wants.
    Claimed,
    /// The caller already held it. An ordinary return — a reinstall, or a
    /// credential that had expired.
    Resumed,
    /// Another identity held it, and the caller's history was merged into it.
    /// The destructive case, which also logs.
    Merged,
}

impl SignIn {
    const fn as_label(self) -> &'static str {
        match self {
            Self::Claimed => "claimed",
            Self::Resumed => "resumed",
            Self::Merged => "merged",
        }
    }
}

/// Publishes every sign-in outcome at zero, so the first sign-in of a
/// deployment's life is a step from 0 to 1 rather than a series appearing —
/// what a panel and a rate query both need. The `as_label` match is
/// exhaustive, so a fourth outcome cannot be added without landing here too.
pub fn describe_sign_ins() {
    for outcome in [SignIn::Claimed, SignIn::Resumed, SignIn::Merged] {
        counter!("ond_sign_ins_total", "outcome" => outcome.as_label()).increment(0);
    }
}

/// Records one completed sign-in.
///
/// Called after the transaction commits, so this counts sign-ins that happened
/// rather than ones that were attempted — a failed one is a refusal the errors
/// module already accounts for.
pub fn sign_in(outcome: SignIn) {
    counter!("ond_sign_ins_total", "outcome" => outcome.as_label()).increment(1);
}
