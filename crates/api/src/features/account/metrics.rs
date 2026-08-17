//! What happens when somebody signs in with Apple.
//!
//! One counter, and it exists because this was the other dark path at launch. A
//! sign-in that merges two identities has always logged — it is destructive and
//! the audit rule requires it — while a first-ever sign-in wrote nothing and
//! counted nothing, so "did anybody create an account today" was a question
//! neither the logs nor `/metrics` could answer. `ond_users_total` counts
//! anonymous identities, which every launch of the app produces whether or not a
//! person ever signs in, so it is not that answer either.
//!
//! A counter and not a line, for the reason docs/observability.md gives: this is
//! a rate. A line per sign-in would read beautifully for a fortnight and then be
//! the thing making the log unreadable.

use metrics::counter;

/// What a sign-in did to the caller's identity.
///
/// The three outcomes are what `repository::sign_in` already branches on, named
/// so the service can record which one happened rather than inferring it. Before
/// this the service could only compare the adopted id to the caller, which tells
/// a merge apart from the other two and cannot tell those two apart — and the
/// pair it could not separate is exactly "a new person" versus "a returning one".
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

/// Publishes every sign-in outcome at zero.
///
/// So the first sign-in of a deployment's life is a step from 0 to 1 rather than
/// a series appearing, which is what a panel and a rate query both need. `SignIn`
/// has no `ALL` of its own; the match below is exhaustive, so a fourth outcome
/// cannot be added without being registered here too.
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
