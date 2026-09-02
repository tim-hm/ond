# Architecture

## Shape

```text
┌──────────────────────────────┐
│  ios/  SwiftUI apps          │
│    Ond          (iOS)        │
│    OndWatch (watchOS)        │
│    OndActivity (iOS)         │  Live Activity extension
│    OndWatchComplication      │  watch face complication
│    └── OndCore               │  one SwiftPM package, three products
│        ├── OndKit            │  domain models + repositories
│        │   └── OndAPI        │  generated protobuf, not a product
│        ├── OndUI             │  design tokens
│        └── OndStyle          │  domain-aware visual primitives
└───────────┬──────────────────┘
            │  gRPC-Web (binary protobuf over HTTP POST)
┌───────────▼──────────────────┐
│  crates/api                  │  one app port + one private metrics port
│    features/technique/       │  handler → service → repository
│    features/profile/         │
│    features/journey/         │
│    features/assistant/       │
│    features/entitlement/     │
│    features/account/         │
│    features/user_technique/  │
└───────────┬──────────────────┘
            │  sqlx, compile-time-checked queries
┌───────────▼──────────────────┐
│  PostgreSQL 18               │  schema owned by crates/migrate
└──────────────────────────────┘

proto/  ──────────────────►  generates both ends
crates/physiology ─────────►  safety facts shared by api and migrate
crates/toolkit ─────────────►  repository tooling invoked by mise
web/    ──────────────────►  the one-pager, served from the same hostname
infra/  ──────────────────►  the box all of the above is deployed onto
```

The two apps and the Live Activity sit on the same three products; the watch face complication draws a mark and one token, so it takes OndUI alone. What the apps share and what they deliberately duplicate is in [code-structure.md](code-structure.md).

## Components

| Component                    | Role                                                                                                                                                    |
| :--------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `proto/`                     | The API contract. The only description of the wire format.                                                                                              |
| `crates/api`                 | The service. Serves gRPC-Web and JSON on public port 18100, plus Prometheus exposition on private port 18103.                                           |
| `crates/migrate`             | Owns the schema and the seeded technique catalogue. Runs to completion and exits.                                                                       |
| `crates/physiology`          | Domain safety thresholds shared by the API's authoring checks and migrate's catalogue checks.                                                           |
| `crates/toolkit`             | Repository tooling behind mise tasks, including migration immutability and voice rendering.                                                             |
| `…/OndCore/Sources/OndAPI`   | Generated protobuf and the Connect client factory. Not a package product, so only OndKit can reach it.                                                  |
| `…/OndCore/Sources/OndKit`   | Domain types, observable models, and repositories. The only Swift code that touches generated types.                                                    |
| `…/OndCore/Sources/OndUI`    | Domain-free design tokens and shared controls.                                                                                                          |
| `…/OndCore/Sources/OndStyle` | Domain-aware visual mappings and drawing primitives shared by the app surfaces. The one package target allowed to know both OndKit and OndUI.           |
| `ios/Ond`                    | The iOS app: composition root plus features.                                                                                                            |
| `ios/OndWatch`               | The watchOS app: the same session over the same package, plus the `WatchConnectivity` link that hands it an identity.                                   |
| `ios/OndActivity`            | The iOS Live Activity extension: lock-screen and Dynamic Island views rendered out of process.                                                          |
| `ios/OndWatchComplication`   | The watchOS complication: the app's mark on a watch face, and a tap that opens it. It states nothing, so it carries no timeline.                        |
| `OndLiveSmoke`               | A development executable in OndCore that exercises the public Swift transport against a running API.                                                    |
| `web/`                       | The one-pager plus the privacy and support pages. Static at serve time, but its figures are generated — Caddy serves it beside the API on one hostname. |
| `infra/`                     | OpenTofu for the single box everything above is deployed onto, plus what runs on it. See [deployment.md](deployment.md).                                |

### Backend features

Each is `crates/api/src/features/<name>/`, laid out handler → service → repository. Only the first is readable without an identity.

| Feature          | Role                                                                                                                                              |
| :--------------- | :------------------------------------------------------------------------------------------------------------------------------------------------ |
| `technique`      | The catalogue: techniques, the stages and phases they play, and the breathing foundations served alongside them.                                  |
| `profile`        | What onboarding collected, from goals down to the display name a leaderboard prints.                                                              |
| `journey`        | Sessions, controlled-pause scores, resting-rate readings, streaks, and leaderboards. Histories are append-only; boards use refreshable snapshots. |
| `assistant`      | A language model reading the profile and the catalogue, and the rules that answer when it cannot. The only feature that spends money.             |
| `entitlement`    | App Store transactions verified against Apple's chain, stored as the tier and expiry `assistant` gates on.                                        |
| `account`        | Sign in with Apple, verified server-side and bound to `users.apple_user_id`. Plus `DeleteAccount`'s erasure.                                      |
| `user_technique` | The exercises a person composed for themselves, bounded by the safe ranges the seeded catalogue publishes.                                        |

## Decisions worth knowing

**PostgreSQL enums, not text columns.** `technique_goal` and `phase_kind` are native enums. The proto contract already fixes both value sets, so the database rejecting a fifth value at write time is strictly better than it reaching a client as something unmapped.

**Stages and phases are child tables.** A technique owns ordered `technique_stages`, and each stage owns ordered `technique_phases` — both keyed on `(…, ordinal)` rather than held as a JSON column on `techniques`. The session is queried as a set and its shape is fixed by the contract; JSON would buy schema flexibility this data does not want, at the cost of the ordering guarantee the keys provide for free. A plain cyclic technique is one stage; the Wim Hof-style protocol, where a retention the person ends sits between fast breaths and a recovery hold, is why the level exists at all.

**The catalogue lives in code.** `crates/migrate/src/seed/catalogue.rs` holds the techniques, breathing foundations, occasions, and progression. Its parent `seed.rs` validates, exports, and reconciles that reference data into the database on every run. Editing the catalogue file and re-running `mise run migrate` is the supported way to change curated content.

**No `shared` crate.** With one service there is no second consumer, so there is nothing to share. Create it when a second crate genuinely needs a type, not before.

**Identity starts as possession of a UUID.** The client mints one on first launch, keeps it in the Keychain so it survives a reinstall, and normally sends it as the `ond-user-id` header. `crates/api/src/identity/` resolves it as middleware; [transport.md](transport.md) has where the layer sits and why. Every feature except the public `TechniqueService` requires an identity, so reading the catalogue never depends on a Keychain write.

For an anonymous row, possession of that id remains the whole claim. A verified Sign in with Apple request changes the state: `features/account/` binds the row to Apple's subject and mints a random device-session credential whose hash is stored in `user_sessions`. Every later request naming that bound id must also present `ond-session-credential`; signing out revokes that device's credential, while account deletion revokes all of them. Signing in is optional and gates no feature. It exists to recover history on another device, and may merge the caller's anonymous history into the identity already bound to that Apple account. The identity module documents that transition; [transport.md](transport.md) documents both headers.

A well-formed id is a claim anybody can make, so `crates/api/src/throttle.rs` rations what one caller may spend: one budget on requests, a far tighter one on creating `users` rows. Its `//!` argues the split and where each number comes from.

**The catalogue is entirely free.** `ListTechniques` takes no identity and returns every technique whole; every seeded row currently sets `requires_subscription` to false. The field remains an advisory client-side gate rather than server authorisation because a session runs entirely on the device and costs the service nothing. What does cost per use is the coach's language model, and `entitlement` guards that against the caller's verified önd+ row. Genuinely withholding catalogue detail would require a different contract rather than treating the existing boolean as security.

## Resolving the caller

`crates/api/src/identity/middleware.rs` decides five outcomes before any handler runs.

| The request carries | The answer |
| :-- | :-- |
| No `ond-user-id` | Passes through untouched. `TechniqueService` is public reference data, so reading the catalogue never gates the first screen on a Keychain write. |
| A malformed `ond-user-id` | `UNAUTHENTICATED`, on any service. A client that sends something is claiming an identity, and a claim that does not parse is a bug worth failing loudly rather than treating as anonymity. |
| A bound id with no `ond-session-credential` | `UNAUTHENTICATED`, before any handler runs. Possession of the id is what this used to accept. A bound row is a history somebody can be handed back on another device, which is worth more than the bare id that names it. |
| An id a sign-in merge folded away | `UNAUTHENTICATED`, and no row is recreated. The honest sender of a dead id is a watch that synced before the phone handed it the adopted identity. Recreating the row would file its sessions on an orphan no sign-in can find. Refused, the client's ledger stays untouched and the sessions go out under the adopted id on a later sync. |
| Anything else | Upserts the row and injects `UserId`. |

**The anonymous path is unchanged.** A row with no `apple_user_id` has nothing to prove, is asked for nothing, and is refused nothing. Local-only mode is the majority of people and is not an account to be locked out of.

The rule is _once bound, always prove_, and it applies to `SignInWithApple` like everything else. A client that has lost its credential but kept a bound id is not stranded: the route back is the one a new device already takes — mint a fresh anonymous id and sign in on that, which hands the bound identity back along with a new credential.

The upsert happens on this path rather than in the first handler that needs a user, because "first sight" is literally the first RPC, whichever one that is: an app that onboards offline and only ever lists techniques still has a row waiting when its profile finally syncs.

A well-formed header is a claim anybody can make, though, and a fresh one each time is a `users` row each time. So creating a row is charged against `throttle::Throttle::spend_new_identity`, and a caller over that budget is refused _instead of_ being written. Merely being an identity stays free: an established client's row already exists, so the branch that spends never runs for them.

## What the coach reads from the catalogue

`features/technique/service.rs::catalogue` is the catalogue as `assistant` reads it, through `features/technique/cache.rs`. The assistant puts every technique in front of the model, checks every slug it says back against that list, and clamps the exercise offers the model proposes against each phase's safe range — which is why the playable stages ride along with the descriptions. It is routed through the service rather than handing the caller a `TechniqueRow`: the row is the feature's SQL shape, and a consumer holding it would make every column on `techniques` part of a contract nobody wrote down. `pub(super)` keeps the cache the only way out, so the derivation stays priced as a once-per-process cost rather than a per-request one.

**What it carries.** `safety_note`, because the cached prompt tells the model never to contradict one. `mechanism`, because the prompt tells the model to name the mechanism — an instruction the coach could only obey out of its own general knowledge while the curated copy stayed behind, which is how the coach and the exercise's own screen came to explain the same breath two different ways.

**What stays behind, and why the difference is the point.** `evidence` is not carried. The mechanism is the confident story and paraphrasing it costs nothing; the evidence section is the one piece of curated copy written specifically not to overclaim, and a model handed it would paraphrase that too — the single place a caveat reliably gets softened. The coach is instructed not to promise outcomes instead, and the honest account reaches the person the one way it cannot be reworded: verbatim, on the exercise's own screen. It still crosses the socket, because reading it costs one column on a query the catalogue needs whole, and skipping it costs a second `SELECT` duplicating the first.

`preparation` is the second unread field, and it did not take the query either. It is short setup copy, read once per process behind the cache, and splitting the query to save it would leave two near-identical `SELECT`s to keep in step — the more expensive mistake. It is also the field most likely to stop being unread: the prefix already orders the coach to name the mechanism, what a body does to shape the breath is the same class of fact, and a coach that cannot say "curl your tongue" is describing the cooling breath the way the screen did before `Manner` existed. Feeding it to `catalogue_lines` beside `caution_clause` is the fix, and it is a prompt change rather than a plumbing one.

## Account lifecycle

`crates/api/src/features/account/repository.rs` holds three writes whose rules do not fit beside the code.

### Sign-in (`sign_in`, `claim`)

Three cases, decided by which row already holds the Apple account. Nobody holds it: the caller's row takes it and keeps its own id — a first sign-in. The caller holds it: nothing to do, and the caller gets its own id back rather than an error. Another row holds it: that row is the person's real history, so the caller's row is merged into it and the device adopts its id — unless the caller is bound to some third Apple account, which is refused.

The refusal in the last two cases is one rule, not two. An identity already bound to an Apple account is never rebound, and both `claim` and `merge` answer `AlreadyBound`. Which one a caller reaches depends only on whether anybody happens to hold the account being signed in to, which is invisible from the device and no basis for the difference between an error and a deletion.

All three run in one transaction, with the holding row locked before anything is read off it: two devices signing into one Apple account at the same moment must not both decide they are first. `users.apple_user_id` is `UNIQUE`, so a race that gets past the lock fails a statement rather than creating a second row.

**Accepted risk — an unbound id is claimable by whoever presents it (TIM-99).** The first case asks for no proof beyond possession of the id, so somebody who obtains an id that has never signed in can bind it to their own Apple account, taking the practice history with it and leaving the victim's device holding an id it can no longer prove. From the server this is indistinguishable from the ordinary case: a person signing in for the first time on the device they have been practising on. It is accepted rather than closed because the exposure is narrow on every axis. An unbound row carries no money, no name and no email — sign-in is required to subscribe — so what is stealable is a breathing log. Obtaining the full id requires the device or its backup: the Settings row and the support-email flow carry only the twelve-hex-digit `SupportReference`, which names a row without being the claim to it. Telling the two cases apart would need the device to prove it has been practising under the id, which is device attestation. `web/privacy.html` claims protection only for signed-in identities, which matches what this gives. Revisit if an unbound row ever carries more.

### Merge (`merge`)

The rule is **reparent then delete**. `into`'s row survives with its own profile answers, `from`'s children move onto it, `from` goes, and the device adopts `into`'s id. Keeping `from` and moving the binding instead would throw away whichever history was older, which is the thing signing in exists to recover.

`from` must be anonymous, and the lock is where that is checked. A row carrying an `apple_user_id` of its own belongs to somebody who proved a different Apple account, and folding it away would destroy the only record that that account has a history — so it is refused as `AlreadyBound`, the same answer `claim` gives the same person by the other branch. Possession of an anonymous id is the whole of the claim to it, and that is not a credential this may weigh against a signed-in one.

Each child table follows from the schema:

- **`sessions`, `bolt_scores`, `resting_rates`** reparent, skipping a row `into` already has. All three are keyed `(user_id, client_<thing>_id)` over a client-minted id, so a key held on both sides is one record that reached the server twice, never two things that happened. It is a `NOT EXISTS` guard because `ON CONFLICT` belongs to `INSERT` and this is an `UPDATE`; the skipped rows stay on `from` and go with the `ON DELETE CASCADE`.
- **`user_techniques`** reparent outright, with no guard. Their ids are server-minted, so two rows can never be one record that arrived twice, and a composed exercise exists nowhere else. This can leave `into` holding more than `MAX_TECHNIQUES`, deliberately: that ceiling gates composing another, and enforcing it here would mean deleting somebody's work to make a number true.
- **`assistant_usage`** sums on a shared date. It is a spend limit counted per person per UTC day, so keeping `into`'s count would let signing in launder whatever `from` had already spent — the same fan-out `entitlement::service`'s `TRANSFER_COOLDOWN` exists to stop, reached by another door.
- **Entitlements are not copied.** They are columns on `users` rather than a child table, so deleting `from` releases its `app_store_original_transaction_id` outright, and the client resubmits its StoreKit transaction on every launch; `entitlement::service::claim` then grants it to `into` against no holder at all. Copying them would mean reasoning about `users_app_store_original_transaction_id_key` and the transfer cooldown for an outcome the next launch produces by itself.

Every statement runs in the caller's transaction. Half a merge is a person whose sessions moved and whose breath-test history did not, with nothing left to say it happened.

**Why `from` is locked `FOR UPDATE` first.** A sync landing on `from` at the same moment — the same device, which has not been told its id is about to change — inserts a child row, and that insert holds `FOR KEY SHARE` on `from`'s `users` row for the life of its transaction. Nothing in the reparents conflicts with that lock, so without the `FOR UPDATE` the sequence is: the reparent runs against a snapshot taken before the insert committed and does not see it, the insert commits, and the `DELETE` then destroys it through `ON DELETE CASCADE`. `FOR UPDATE` conflicts with `FOR KEY SHARE`, so the merge waits for the in-flight write instead of stepping over it, and because each statement takes its own snapshot under READ COMMITTED the reparents see everything the lock waited for. A write that starts after the lock is held blocks, then fails its foreign key once `from` is gone; the client resends under the id it has by then adopted, or is refused by the merge tombstone rather than recreated as an orphan. The lock also doubles as the existence check the `DELETE` would otherwise need, and reads the binding the anonymity check turns on.

### Erasure (`delete_account`)

One `DELETE`, because the schema already says what erasure means. `sessions` and `bolt_scores` (`0005_journey.sql`), `resting_rates` (`0022_resting_rates.sql`), `assistant_usage` (`0006_assistant_quota.sql`) and `user_sessions` (`0018_user_sessions.sql`) are all `ON DELETE CASCADE`, which is how erasure revokes every credential the identity ever minted without naming one. The profile answers are columns on `users` itself (`0004_users_and_profiles.sql`), and the App Store binding is two more columns, released here exactly as `merge` releases the identity it folds away — so the transaction is free to entitle whoever presents it next. What Apple revoked is not released with it: `revoked_transactions` is filed against the purchase rather than the person.

The lock is not `merge`'s. That one stops a concurrent write being cascaded away while the row survives, a hazard erasure does not have — nothing survives here, so a sync holding `FOR KEY SHARE` merely makes this wait, and whatever it committed goes with the cascade. This lock guards the _decision_: `service::delete_account` reads the binding, then verifies a credential against Apple, a network round trip no transaction may be held across. Between those two moments a concurrent `SignInWithApple` can bind the row. So `bound_to` carries what was actually proved, and a binding that has changed under the caller refuses rather than erasing an Apple account nobody presented a credential for.

A row that is already gone is not an error, and that is why this reads before it writes rather than checking `rows_affected`: the middleware has just created the row if it were missing, so the only way to find none is a second deletion of the same identity.

What this cannot defend against is the request _after_ it. `identity::resolve` upserts a row for any well-formed id it holds no merge tombstone for, so a client that goes on sending the erased id recreates it empty. `DeleteAccount` therefore requires the device to mint a fresh identity before it sends anything else, and the e2e suite pins that behaviour.

## App Store entitlement verification

`crates/api/src/features/entitlement/verifier/` checks a client's `Transaction.jwsRepresentation` in-process. `appstore.rs` reads the App Store's transaction format; `chain.rs` decides whether a certificate chain is Apple's and knows nothing else.

### Why the check is written out rather than pulled in

Apple ships an `app-store-server-library` for Java, Node, Swift, and Python, and not for Rust. There is one well-maintained community port (`app-store-server-library`, about 200k downloads a quarter), and it was the obvious candidate. Three things decided against it.

- **48 new crates against 16.** It carries typed structs for the whole App Store Server API — notifications, renewal info, the Advanced Commerce schema — and the crypto to match, including RSA and Ed25519 stacks this binary has no other use for. What is used here is one P-256 signature type. The local route adds no cryptographic implementation at all: `ring` is already linked through rustls, and everything new is DER parsing.
- **It does not check certificate validity dates**, and its chain walk carries a `TODO: Implement issuer checking`. Both are defensible choices made for reasons this app does not share, and neither should be inherited silently in the one place where a signature check decides who gets to spend money.
- **The surface actually needed is one function.** Verifying a client's `Transaction.jwsRepresentation` is the only thing this server does with the App Store. There is no Server API client, no notification endpoint, and deliberately no plan for one at V1.

The trade is that Apple's payload schema is transcribed here rather than tracked upstream. It is bounded, because only six fields are read and `serde` ignores additive JSON by default.

### What the check is

Apple's own libraries define it, and this follows them step for step: exactly three certificates in `x5c`, leaf first; `alg` must be `ES256`; the leaf and the intermediate must each carry Apple's marker extension; every certificate must have been valid when the transaction was signed; and the chain must lead to Apple Root CA - G3. The bundle id is checked against `config::BUNDLE_ID`, shared with the Sign in with Apple verifier so the two cannot come to mean different apps.

Validity is judged at the moment the transaction was signed, not now. Apple's leaf certificates rotate roughly yearly and the old ones expire, while a subscription's JWS is signed once at renewal and resubmitted for a year afterwards. Measuring against `now()` would reject genuine transactions on Apple's rotation schedule, which is what broke validators industry-wide in September 2023 and again in October 2025.

The intermediate must also be _allowed_ to have issued the leaf, which is a separate question from whether it did. `basicConstraints` and `keyUsage` answer it. The chain walk alone would be satisfied by an end-entity certificate sitting directly under the G3 root. Apple does not issue such a certificate carrying the WWDR marker OID, so requiring both fields is defence in depth rather than a hole — worth closing because this is the one place a signature decides who spends money. An intermediate that omits either is not a CA certificate any conforming path validator would accept, so demanding them rejects nothing Apple issues.

### What the check cannot see

A `jwsRepresentation` is a signed claim about a moment, not a live read of a subscription. A refund issued after the client last synced is invisible here until StoreKit hands the client the revoked transaction. That is what deferring App Store Server Notifications costs, and it is affordable because the worst case is honouring a refunded year — not because the gap is not real.

### What it rejects that you might not expect

Transactions minted by Xcode's local StoreKit configuration file (`ios/Ond/Ond.storekit`) are signed by a per-machine test certificate, not by Apple. Simulator purchases therefore verify locally, entitle the UI locally, and are refused here — which is the offline-first design working rather than failing, since nothing on screen waits on this call. Exercising the server half needs a sandbox tester on a real device; exercising what the server _does_ with an entitlement needs only `UPDATE users SET subscription_tier = …, subscription_until = …`.

### The price list

`PRODUCTS` is one subscription at two cadences, so both rows name the same tier: what a person bought is önd+, and how often they are billed for it is Apple's business. Both live in one App Store subscription group, which makes switching Apple's problem — a person holds at most one at a time, and crossgrading issues a fresh transaction naming the other. A `productId` in neither row is `NotOurs`, including the two-tier ids this app used to sell, because an entitlement is only ever granted for something currently on the price list.

The ids have to match `ios/Ond/Ond.storekit`, `SubscriptionPlan.productIdentifier` in `OndKit`, and App Store Connect. A mismatch presents at runtime as a paywall with no price and a purchase that never verifies, silently, because `Product.products(for:)` answers an unknown id with an empty array rather than an error. Two of the three are pinned: `the_storekit_configuration_sells_exactly_what_this_server_honours` reads the StoreKit file rather than restating it — though that file is a simulator-only input that never ships, so what it proves is that the local development story matches this list, not that the App Store does — and `productIdentifiersAreTheOnesTheServerHonours` in `SubscriptionGatingTests` pins the ids the shipped app actually asks for. App Store Connect cannot be reached from any test and is only ever confirmed by a purchase completing on a real build.

### Sandbox transactions are honoured

Apple signs Sandbox transactions with the same production certificate chain as real ones, so the chain walk cannot separate them and the payload's `environment` field is the only thing that can. It is read despite the standing rule against carrying fields nothing acts on.

Both environments are honoured deliberately. A TestFlight build points at the production API — that is the whole point of testing against production — but transacts in Sandbox. Refusing `Sandbox` would leave every beta tester unable to subscribe. So the environment is recorded and reported, not gated on, and the boundary says so out loud when a sandbox purchase is honoured by a production deployment.

The tightening path, once a beta window closes, is to refuse `Sandbox` when `config::Environment::Production` is in force. Doing that before then trades a small, team-only abuse surface for a broken beta. That refusal belongs in `TransactionVerifier::verify` rather than the service, so that "verified" means one thing and no later caller has to remember the check. It sits on `StoreEnvironment` today only because nothing refuses anything yet; the day it starts deciding, `AppStoreVerifier` should take the expected environment at construction — `main.rs` already holds `config.environment` there — and the field become its output rather than its input.

`StoreEnvironment::Unknown` is its own variant rather than folded into `Sandbox`. Folding would read as "we know this is sandbox" when the truth is "we could not tell", and the moment the tightening lands that lie would refuse a genuine production purchase whose payload Apple has reshaped. A tightening must therefore refuse `Sandbox` only, and treat `Unknown` as production-or-unknown: entitle, and say so where somebody will see it.

## Composed exercises

`crates/api/src/features/user_technique/validation.rs` decides what a person may store as an exercise. Each phase duration is checked against `PhaseLimits`, the range the seeded catalogue derives for that phase kind. One rule cannot be stated that way, and `reject_a_timed_hold_after_fast_breathing` holds it.

**Fast breathing and a timed hold may not appear in the same technique.** Hyperventilation followed by a measured breath-hold is the documented way to faint doing this: the carbon dioxide that would make somebody breathe has been blown off, so the urge arrives after the oxygen has gone rather than before. Both numbers — what counts as fast, and what counts as a hold worth beating — come from `physiology::breathes_fast` and `physiology::TIMED_HOLD_CEILING_MS`.

**It cannot be a per-phase check.** `PhaseLimits` is aggregated per phase kind across every closed stage in the catalogue, so it has already forgotten which technique a range came from. Every phase of a dangerous draft can sit inside its own range while the combination does not. The floors it derives are enough to compose fifty breaths a minute; whether the ceilings are enough to follow them with a target depends on what the catalogue happens to seed, which is exactly why the rule cannot be left to them.

**It spans the whole technique**, not only the stages after the fast one. `rounds` replays the stage list, so a hold composed _before_ the fast breathing follows it on every round but the first. The seed-side rule in `crates/migrate` — `no_hold_after_fast_breathing_is_a_target` — reasons the same way and reads the same two constants. That one has a second escape this has not: a seeded stage may be open-ended, so the person ends the hold and there is nothing to reach, where an authored stage cannot be. `user_technique_stages` has no such column, on 0012's reasoning that authoring one should be unrepresentable.

**Today it refuses nothing.** The widest hold the catalogue derives is the Wim Hof recovery dial's own top, which is the ceiling itself, so no draft can currently exceed it. Two figures with no link between them landing on the same value used to be a coincidence; the limits test in `crates/api/tests/e2e` now asserts it, so seeding a slow technique with a longer closed hold fails there rather than raising the ceiling a person may author to without anybody deciding it should rise.

## Pulse trace geometry

`PulseTrace.runs()` in `OndKit` turns a session's heart-rate readings into the points a chart draws. Six decisions shape the result.

**Unit space.** The points are `CGPoint` in unit space, which is already how `TechniqueFigure` carries a normalised drawing through this module, and is what `Path.addLines` takes — so the one thing that draws these maps straight into a path.

**The x = 1 endpoint.** x = 1 is the session's end rather than the last reading's — see `span`. A wrist that shared for the whole session reaches it either way. One that stopped early stops where it stopped, which is the only honest place for the line to end.

**Runs rather than one line.** The readings stop and start. A paused session ends the arrangement and a resumed one makes a fresh arrangement; a wrist can go out of range and come back. Joined up, those minutes draw as one straight segment across the middle of the chart — a heart rate nothing measured, stated with exactly the confidence of the parts that were. Broken, they draw as the gap they are.

**The break threshold.** A run ends at `PulseMonitor.staleness`, which is already this feature's answer to "the readings have stopped" — the same silence that blanks the badge mid-session ends a run here. A lost message or two falls under it and stays joined, which is what that threshold was chosen for.

**Both axes normalised to this session.** A fixed axis — nought to two hundred — draws every settling as the same flat line, and the whole reason to show this is that the shape is legible. The cost is that the drawing says nothing about magnitude on its own, which is what `range` is for beside it.

**A flat heart draws down the middle.** A heart that held one rate the whole way through has no spread to divide by and comes back level. That is the honest drawing of it: it neither fell nor rose.

## What runs where

Locally, only PostgreSQL is containerised (`compose.yaml`); the API runs natively under `mise run dev` so a code change rebuilds in seconds. [contributing.md](contributing.md) is the whole of that surface.

Deployed, everything is containerised on one box provisioned by OpenTofu from `infra/`: the API, Postgres, and a Caddy that fronts both the RPC surface and `web/`. There is still no Kubernetes and no Tilt — one box is the deliberate ceiling for V1, and [deployment.md](deployment.md) has the topology and, more usefully, where each of its decisions runs out.
