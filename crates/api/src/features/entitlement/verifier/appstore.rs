//! Checks an App Store signed transaction against Apple's root, in-process.
//! Three certificates in `x5c`, `ES256`, Apple's marker extensions, validity at
//! `signedDate`, and a chain reaching Apple Root CA - G3. `super::chain` owns
//! everything after `alg`. See docs/architecture.md, "App Store entitlement
//! verification".

use chrono::{DateTime, Utc};
use serde::Deserialize;

use super::{StoreEnvironment, TransactionVerifier, VerificationError, VerifiedTransaction, chain};
use crate::config::BUNDLE_ID;
use crate::features::entitlement::types::SubscriptionTier;
use crate::jws;

/// Everything this app sells, and what each one buys. One subscription at two
/// cadences, so both rows name the same tier. A `productId` in neither row is
/// `NotOurs`. These ids also live in `ios/Ond/Ond.storekit`, in `OndKit`, and in
/// App Store Connect, and a mismatch presents as a paywall with no price. See
/// docs/architecture.md, "App Store entitlement verification".
const PRODUCTS: &[(&str, SubscriptionTier)] = &[
    ("xyz.holmie.ond.plus.monthly2", SubscriptionTier::Plus),
    ("xyz.holmie.ond.plus.yearly", SubscriptionTier::Plus),
];

/// The only algorithm Apple signs transactions with.
///
/// Compared against the header rather than inferred from the key, which is what
/// closes the classic JWS confusion attacks: `none`, and anything that would
/// have the signature checked as a MAC keyed on a public value.
const SIGNING_ALGORITHM: &str = "ES256";

/// The verifier a deployment runs.
///
/// Stateless, and therefore a unit struct: the trust anchor is compiled into
/// `chain` and the certificate chain arrives with each transaction, so there
/// is nothing to build and nothing to configure.
pub struct AppStoreVerifier;

impl TransactionVerifier for AppStoreVerifier {
    fn verify(&self, signed_transaction: &str) -> Result<VerifiedTransaction, VerificationError> {
        let segments = jws::split(signed_transaction)?;

        let header: JwsHeader = segments.header_json()?;
        if header.alg != SIGNING_ALGORITHM {
            return Err(VerificationError::Untrusted(format!(
                "`alg` is `{}`, not {SIGNING_ALGORITHM}",
                header.alg
            )));
        }

        // Read before the chain is checked: the certificates' validity windows
        // are measured against `signedDate`, so a transaction signed three years
        // ago still verifies after its leaf expired. Nothing read here is
        // believed until the signature below succeeds, and a forged `signedDate`
        // still has to produce a chain leading to Apple's root.
        let payload: TransactionPayload = segments.payload_json()?;
        let signed_at = timestamp(payload.signed_date, "signedDate")?;

        chain::verify(
            &header.x5c,
            segments.signing_input,
            &segments.signature,
            signed_at,
        )?;

        payload.into_verified()
    }
}

/// The JWS header, of which only two fields matter.
#[derive(Deserialize)]
struct JwsHeader {
    alg: String,

    /// Leaf first, each certificate signed by the next, per RFC 7515. The last
    /// entry is Apple's root and is never read.
    #[serde(default)]
    x5c: Vec<String>,
}

/// The subset of Apple's `JWSTransactionDecodedPayload` anything here acts on.
///
/// Six fields of about thirty. The rest — storefront, quantity, purchase date,
/// ownership type — would each be a field to keep in step with a schema Apple
/// owns and changes, in exchange for nothing that decides an entitlement.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransactionPayload {
    bundle_id: String,
    product_id: String,
    transaction_id: String,
    original_transaction_id: String,

    /// Which App Store signed this. Carried without being acted on: the
    /// certificate chain cannot separate `Production` from `Sandbox`, and
    /// [`StoreEnvironment`] says why both are honoured. Optional so a payload
    /// Apple reshapes reads as unknown rather than refusing a real purchase.
    environment: Option<String>,

    /// Epoch milliseconds. Absent on a non-renewing product, which is not
    /// something this app sells — see [`TransactionPayload::into_verified`].
    expires_date: Option<i64>,

    /// Epoch milliseconds, present only for a refund or a revocation.
    revocation_date: Option<i64>,

    /// Epoch milliseconds. The instant the certificate chain is judged against.
    signed_date: i64,
}

impl TransactionPayload {
    /// The last two checks, which are about identity rather than trust: a
    /// perfectly genuine Apple signature over somebody else's app, or over a
    /// product this app does not sell, entitles nobody here.
    fn into_verified(self) -> Result<VerifiedTransaction, VerificationError> {
        if self.bundle_id != BUNDLE_ID {
            return Err(VerificationError::NotOurs(format!(
                "`bundleId` is `{}`, not `{BUNDLE_ID}`",
                self.bundle_id
            )));
        }

        let Some((_, tier)) = PRODUCTS
            .iter()
            .find(|(product_id, _)| *product_id == self.product_id)
        else {
            return Err(VerificationError::NotOurs(format!(
                "`productId` is `{}`, which this app does not sell",
                self.product_id
            )));
        };

        let expires_date = self.expires_date.ok_or_else(|| {
            VerificationError::NotOurs(
                "the transaction has no `expiresDate`, so it is not a subscription".to_owned(),
            )
        })?;

        // Absent or unrecognised reads as `Unknown` rather than being guessed
        // either way — see `StoreEnvironment::Unknown` for why guessing sandbox
        // would be the more expensive mistake. Nothing is refused on it.
        let environment = StoreEnvironment::parse(self.environment.as_deref());

        Ok(VerifiedTransaction {
            environment,
            transaction_id: self.transaction_id,
            original_transaction_id: self.original_transaction_id,
            tier: *tier,
            expires_at: timestamp(expires_date, "expiresDate")?,
            signed_at: timestamp(self.signed_date, "signedDate")?,
            revoked_at: self
                .revocation_date
                .map(|at| timestamp(at, "revocationDate"))
                .transpose()?,
        })
    }
}

fn timestamp(millis: i64, field: &str) -> Result<DateTime<Utc>, VerificationError> {
    DateTime::from_timestamp_millis(millis).ok_or_else(|| {
        VerificationError::Malformed(format!("`{field}` is not a representable time"))
    })
}

#[cfg(test)]
mod tests {
    use base64::Engine as _;
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;

    use super::*;

    /// A structurally perfect JWS carrying a chain that is nobody's.
    fn forged(payload: &str) -> String {
        let header =
            URL_SAFE_NO_PAD.encode(br#"{"alg":"ES256","x5c":["MIIBBg==","MIIBBg==","MIIBBg=="]}"#);
        format!(
            "{header}.{}.{}",
            URL_SAFE_NO_PAD.encode(payload),
            URL_SAFE_NO_PAD.encode([0_u8; 64])
        )
    }

    fn payload_json() -> String {
        let (product_id, _) = PRODUCTS[0];
        format!(
            r#"{{"bundleId":"{BUNDLE_ID}","productId":"{product_id}",
                 "transactionId":"2000000000000042",
                 "originalTransactionId":"2000000000000001",
                 "expiresDate":1800000000000,"signedDate":1770000000000}}"#
        )
    }

    /// A payload this server would honour, for the tests that change one field
    /// and assert it no longer would.
    fn payload() -> TransactionPayload {
        TransactionPayload {
            bundle_id: BUNDLE_ID.to_owned(),
            product_id: PRODUCTS[0].0.to_owned(),
            transaction_id: "2000000000000042".to_owned(),
            original_transaction_id: "2000000000000001".to_owned(),
            environment: Some("Production".to_owned()),
            expires_date: Some(1_800_000_000_000),
            revocation_date: None,
            signed_date: 1_770_000_000_000,
        }
    }

    /// Everything about this token is well-formed and none of it is Apple's, so
    /// it must not entitle anybody. `chain` pins what the walk itself refuses;
    /// this pins that a submission still goes through the walk. Without it,
    /// deleting the `chain::verify` call would leave this file's tests passing.
    #[test]
    fn a_verified_transaction_still_has_to_reach_apples_root() {
        let error = AppStoreVerifier
            .verify(&forged(&payload_json()))
            .expect_err("a self-signed chain is not Apple's");

        assert!(matches!(error, VerificationError::Untrusted(_)), "{error}");
    }

    /// `alg` is read from the header and compared, rather than inferred from
    /// the key: an unchecked header is how a JWS verifier gets talked into
    /// accepting `none`.
    #[test]
    fn an_unsigned_token_is_refused_before_anything_else() {
        let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"none","x5c":[]}"#);
        let token = format!("{header}.{}.", URL_SAFE_NO_PAD.encode(payload_json()));

        let error = AppStoreVerifier
            .verify(&token)
            .expect_err("`none` is not a signature");

        assert!(
            matches!(&error, VerificationError::Untrusted(message) if message.contains("ES256")),
            "{error}"
        );
    }

    /// Three segments, and only three. A token missing its signature must fail
    /// as malformed rather than reaching a code path that treats an absent
    /// signature as an empty one.
    #[test]
    fn a_token_that_is_not_a_jws_is_malformed() {
        for token in ["", "not-a-jws", "one.two", "one.two.three.four"] {
            let error = AppStoreVerifier
                .verify(token)
                .expect_err("a token of the wrong shape is not a JWS");

            assert!(matches!(error, VerificationError::Malformed(_)), "{token}");
        }
    }

    /// The bundle-id check is what stops a genuine Apple receipt for a
    /// different app from buying anything here. It runs after the signature, so
    /// this asserts the rule directly rather than through a token no test can
    /// mint.
    #[test]
    fn a_transaction_for_another_app_is_not_ours() {
        let error = TransactionPayload {
            bundle_id: "com.example.other".to_owned(),
            ..payload()
        }
        .into_verified()
        .expect_err("another app's bundle id entitles nobody here");

        assert!(matches!(error, VerificationError::NotOurs(_)), "{error}");
    }

    /// Likewise for a product this app does not sell — a future consumable, a
    /// receipt from another of the same developer's apps, or the Coach
    /// subscription the single-tier collapse withdrew.
    #[test]
    fn a_transaction_for_another_product_is_not_ours() {
        for product_id in [
            "xyz.holmie.ond.something.else",
            "xyz.holmie.ond.coach.monthly",
        ] {
            let error = TransactionPayload {
                product_id: product_id.to_owned(),
                ..payload()
            }
            .into_verified()
            .expect_err("a product not on the price list entitles nobody");

            assert!(
                matches!(error, VerificationError::NotOurs(_)),
                "{product_id}: {error}"
            );
        }
    }

    /// Both ids are asserted because a typo in either presents as a genuine
    /// purchase this server refuses, which nothing else would catch. Both must
    /// buy the same tier: the yearly plan is a cadence, not a product.
    #[test]
    fn both_cadences_buy_the_one_tier() {
        for (product_id, _) in PRODUCTS {
            let verified = TransactionPayload {
                product_id: (*product_id).to_owned(),
                ..payload()
            }
            .into_verified()
            .expect("a product on the price list is ours");

            assert_eq!(verified.tier, SubscriptionTier::Plus, "{product_id}");
        }
    }

    /// The whole ordering rule rests on this field reaching the service, and it
    /// arrives in the same milliseconds every other date does.
    #[test]
    fn the_signed_date_travels_with_the_transaction() {
        let verified = payload().into_verified().expect("the payload is ours");

        assert_eq!(verified.signed_at.timestamp(), 1_770_000_000);
    }

    /// The original id binds the subscription lineage to one person; the
    /// transaction id identifies the individual renewal a refund can revoke.
    /// Conflating them makes a refund for one period revoke every later one.
    #[test]
    fn the_individual_transaction_id_travels_separately_from_its_lineage() {
        let verified = payload().into_verified().expect("the payload is ours");

        assert_eq!(verified.transaction_id, "2000000000000042");
        assert_eq!(verified.original_transaction_id, "2000000000000001");
    }

    /// Apple sends epoch **milliseconds**. Reading one as seconds lands in the
    /// year 58000 and silently grants a subscription that never expires, which
    /// is exactly the kind of bug no other test would notice.
    #[test]
    fn dates_are_read_as_milliseconds() {
        let verified = TransactionPayload {
            revocation_date: Some(1_790_000_000_000),
            ..payload()
        }
        .into_verified()
        .expect("the payload is ours");

        assert_eq!(verified.expires_at.timestamp(), 1_800_000_000);
        assert_eq!(
            verified.revoked_at.map(|at| at.timestamp()),
            Some(1_790_000_000)
        );
    }

    #[test]
    fn a_production_transaction_is_read_as_production() {
        let verified = payload().into_verified().expect("the payload is ours");

        assert_eq!(verified.environment, StoreEnvironment::Production);
    }

    /// Apple signs sandbox transactions with the same production chain, so
    /// nothing before this point can tell them apart. It must still entitle: a
    /// `TestFlight` build points at the production API and transacts in Sandbox,
    /// so refusing here would leave every beta tester unable to subscribe.
    #[test]
    fn a_sandbox_transaction_is_read_as_sandbox_and_still_entitles() {
        let verified = TransactionPayload {
            environment: Some("Sandbox".to_owned()),
            ..payload()
        }
        .into_verified()
        .expect("a sandbox purchase is honoured");

        assert_eq!(verified.environment, StoreEnvironment::Sandbox);
        assert_eq!(verified.tier, SubscriptionTier::Plus);
    }

    /// The `PRODUCTS` drift, made mechanical. This reads the `StoreKit`
    /// configuration rather than restating it, because a fixture listing the ids
    /// again would be another copy to drift.
    #[test]
    fn the_storekit_configuration_sells_exactly_what_this_server_honours() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../ios/Ond/Ond.storekit");
        let raw = std::fs::read_to_string(path)
            .unwrap_or_else(|error| panic!("{path} should be readable: {error}"));
        let configuration: serde_json::Value =
            serde_json::from_str(&raw).expect("the StoreKit configuration should be valid JSON");

        let mut configured: Vec<&str> = configuration["subscriptionGroups"]
            .as_array()
            .expect("the configuration should declare subscription groups")
            .iter()
            .flat_map(|group| {
                group["subscriptions"]
                    .as_array()
                    .expect("each group should declare subscriptions")
                    .iter()
                    .map(|subscription| {
                        subscription["productID"]
                            .as_str()
                            .expect("each subscription should carry a productID")
                    })
            })
            .collect();
        configured.sort_unstable();

        let mut honoured: Vec<&str> = PRODUCTS.iter().map(|(product_id, _)| *product_id).collect();
        honoured.sort_unstable();

        assert_eq!(
            configured, honoured,
            "ios/Ond/Ond.storekit and this file's PRODUCTS disagree; \
             a mismatch is a paywall with no price and a purchase that never verifies"
        );
    }

    /// An absent or reshaped `environment` is `Unknown` — never quietly folded
    /// into `Sandbox`, which would later have the tightening refuse a genuine
    /// production purchase whose payload Apple had changed. And it must not
    /// refuse one now either: a payload Apple has reshaped still buys what it
    /// says it buys.
    #[test]
    fn an_unreadable_environment_is_unknown_rather_than_assumed() {
        for raw in [None, Some("Xcode".to_owned()), Some(String::new())] {
            let verified = TransactionPayload {
                environment: raw.clone(),
                ..payload()
            }
            .into_verified()
            .expect("an unknown environment does not refuse a purchase");

            assert_eq!(
                verified.environment,
                StoreEnvironment::Unknown,
                "{raw:?} should read as unknown"
            );
            assert_eq!(verified.tier, SubscriptionTier::Plus, "{raw:?}");
        }
    }
}
