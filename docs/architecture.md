# Architecture

## Shape

```text
┌──────────────────────────────┐
│  ios/  SwiftUI apps          │
│    Ond          (iOS)        │
│    OndWatch (watchOS)        │
│    OndActivity (iOS)         │  Live Activity extension
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

All three shipping targets sit on the same three products. What the apps share and what they deliberately duplicate is in [code-structure.md](code-structure.md).

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

## What runs where

Locally, only PostgreSQL is containerised (`compose.yaml`); the API runs natively under `mise run dev` so a code change rebuilds in seconds. [contributing.md](contributing.md) is the whole of that surface.

Deployed, everything is containerised on one box provisioned by OpenTofu from `infra/`: the API, Postgres, and a Caddy that fronts both the RPC surface and `web/`. There is still no Kubernetes and no Tilt — one box is the deliberate ceiling for V1, and [deployment.md](deployment.md) has the topology and, more usefully, where each of its decisions runs out.
