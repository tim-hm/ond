# Contributing

## Prerequisites

- **[mise](https://mise.jdx.dev)** — installs and pins every other tool. Nothing else needs installing by hand.
- **Docker** (OrbStack or Docker Desktop) — runs PostgreSQL, and nothing else.
- **Xcode** — required for the iOS app. The Command Line Tools alone are not enough.

### Point the toolchain at Xcode (one time, required)

Installing Xcode does not change the active developer directory. Until you switch it, `swiftlint` fails to load `sourcekitd` and Swift Testing is missing entirely — both with errors that look like broken configuration rather than a missing toolchain:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch     # accepts the licence, installs components
```

Verify with `xcode-select -p`; it should print the Xcode path, not `/Library/Developer/CommandLineTools`.

## First run

```bash
mise install          # every pinned tool
mise run migrate      # starts Postgres, creates the DB, migrates, seeds
mise run dev          # API on :18100
```

In another terminal:

```bash
curl -s localhost:18100/health
grpcurl -plaintext localhost:18100 ond.v1.TechniqueService/ListTechniques
```

Then the app:

```bash
mise run ios:open     # generates Ond.xcodeproj and opens it
```

Pick any iPhone simulator and press ⌘R. You should see eleven techniques, served from your local Postgres.

## Ports

| Service    | Port  | Notes                                                |
| :--------- | :---- | :--------------------------------------------------- |
| API        | 18100 | gRPC-Web and JSON on the same listener               |
| PostgreSQL | 18101 | `mise run db:psql` to query it                       |
| `web/`     | 18102 | `mise run web:serve`, static preview only            |
| Metrics    | 18103 | Prometheus scrape target, never published            |
| Grafana    | 18104 | `tailscale serve` on the box. Not 443 — Caddy has it |

**önd owns 18100–18199.** Every port this repo uses comes from that block, and nothing else on the machine should claim it — one range means one thing to remember and one thing to check.

The block is chosen to clear the sibling `connect` repo, which reserves 15432, 15433, 17233, 17474, 17687, 18080–18092, and 19000. That matters more than it sounds: connect's Tilt binds `127.0.0.1:15432`, which beats a container's `*:15432` binding for anything resolving `localhost`, so an önd process pointed at 15432 would silently read and write connect's database. If you add a service, take the next free number in 18100–18199.

## The gate

```bash
mise run generate   # 1. protobuf types + SQLx cache
mise run fmt        # 2. format
mise run check      # 3. full validation
```

`mise run check` covers Rust, protobuf, doc links, and the formatting of everything that is not Rust or Swift — markdown, YAML, JSON, and TOML all go through `vp` (`check:text`), with `check:md` layering markdown's own rules on top. It deliberately excludes `check:swift` and `test:swift`, which need the Xcode toolchain — run those yourself when touching `ios/`.

### Breaking the protobuf contract on purpose

`check:proto` compares `proto/` against `main` and fails on a breaking change, because a released client would break with it. Until one has shipped there is nothing to protect, and a contract that cannot be corrected before its first release is worse than one that can — replacing `Technique.phases` with `stages` was taken for exactly that reason, while no released client existed to break.

The single-run override:

```bash
PROTO_BREAKING_ACK='replaces Technique.phases with stages; no client has shipped' mise run check
```

It is per-invocation, it still runs `buf breaking` and prints every finding, and it asks for a sentence rather than a flag. Nothing about it persists: once the commit is on `main` the comparison is against the new shape and the check passes unaided, so reaching for this twice in a row means the first break was never merged — or that the contract now has clients and the change needs a new field instead.

CI (`.github/workflows/checks.yml`) runs the formatting and lint subset on every push to `main` and every pull request: `check:rs`, `check:proto`, `check:text`, `check:md`, and `check:doc-links` on Linux, plus `check:swift` on macOS. Tests and the drift checks (`check:sqlx`, `check:generated`) remain local — CI has neither a database nor BSR access — so the full gate is still `mise run check` before committing.

## Common tasks

| Intent                         | Command                                                                       |
| :----------------------------- | :---------------------------------------------------------------------------- |
| Wipe and rebuild the database  | `mise run dev:db:reset`                                                       |
| Query the database             | `echo 'select * from techniques;' \| mise run db:psql`                        |
| Grant yourself Coach locally   | `mise run dev:coach [user-id]` — then `mise run dev` calls the real model     |
| Change the technique catalogue | Edit `crates/migrate/src/seed.rs`, then `mise run migrate`                    |
| Change the API contract        | Edit `proto/ond/v1/…`, then `mise run generate`                               |
| Add a Swift file               | Create it under `ios/Ond/` or `ios/OndWatch/`; `mise run ios:gen` picks it up |
| Build the apps headlessly      | `mise run ios:build`, `mise run ios:build:watch`                              |
| Ship a beta                    | `mise run ios:testflight` — see below                                         |

## Releasing to TestFlight

One archive carries both apps: the phone target embeds the watch app, and a companion watch app is not a submission of its own.

```bash
mise run ios:archive      # signed archive in ios/build/Ond.xcarchive
mise run ios:testflight   # archives, re-signs for distribution, uploads
```

Three values, all machine-local and all in `.env`, which `.mise.toml` loads:

| Variable            | What it is                                                                |
| :------------------ | :------------------------------------------------------------------------ |
| `OND_DEV_TEAM`      | the ten-character Apple Developer team id, substituted into `project.yml` |
| `OND_ASC_KEY_ID`    | App Store Connect API key id                                              |
| `OND_ASC_ISSUER_ID` | that key's issuer id                                                      |

The key's `.p8` is a file rather than a value and never goes in `.env`: put it at `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`, the path Apple's own tooling searches, which is why only the id is configured. Create the key under **Users and Access → Integrations → App Store Connect API** with the **Admin** role — App Manager can upload but cannot mint the distribution certificate the first export needs — and note that the `.p8` downloads exactly once.

Both tasks refuse with an explanation rather than a signing error when something is missing, so running them is the fastest way to find out what you still need.

Two things the tasks decide for you. The **build number is the commit count** (`git rev-list --count HEAD`), because App Store Connect refuses a number it has already accepted; two archives of the same commit collide, and the answer to that is a commit. The **version** is `MARKETING_VERSION` in `project.yml`, set at project level so the watch app cannot disagree with its host — a mismatch fails validation.

Xcode signs the archive itself with the _development_ certificate; distribution signing is applied when `ios:testflight` exports it. That is why an archive is worth taking on a machine that has no distribution certificate yet.

## Things that will bite you

**A stale `DATABASE_URL` in your shell.** If you have used the `connect` repo in the same terminal, `DATABASE_URL` is exported and points at its database. Running `cargo run -p migrate` directly then targets the wrong cluster; sqlx aborts before applying anything, but the error is confusing. Always go through `mise run`, which supplies its own.

**The coach calls Bedrock for real, from your machine.** `mise run dev` pins `AWS_PROFILE=ond-dev`, because the assistant takes no provider key — it signs through the AWS SDK's default credential chain, and unset, that chain reads whichever `[default]` profile the machine holds, which on a laptop carrying several accounts is somebody else's. `ond-dev` is not the admin `ond` profile that applies infrastructure: it assumes the `ond-dev` role, which carries the box's own invoke-model policy and nothing else, so the process you leave running all day holds a credential that can call one API. It is a stanza in `~/.aws/config` with no keys of its own (`mise run infra:apply` prints the `role_arn` as `dev_role_arn`; in this account it is):

```ini
[profile ond-dev]
role_arn = arn:aws:iam::136339248297:role/ond-dev
source_profile = ond
region = eu-west-2
```

Two gates keep the bill small: only the Coach tier ever claims a model call, so a local user answers from the rules until `mise run dev:coach` grants the entitlement, and past that the allowance is 50 calls a day per identity on the cheapest model available. With no `ond-dev` profile configured the credential probe fails at boot and you get the rule-based fallback, logged with what to do about it:

```text
INFO the assistant cannot reach Bedrock — answering from the rule-based fallback
     error=no AWS credentials are available remedy=add the ond-dev assume-role stanza to ~/.aws/config — docs/contributing.md shows it
```

That is the supported state for a fresh clone and for CI, not a broken one.

**The Xcode project is generated.** `ios/Ond.xcodeproj` is gitignored and rebuilt from `ios/project.yml`. Changing build settings in Xcode's UI works until the next `mise run ios:gen` throws it away — make the change in `project.yml` instead.

**Device builds need signing; the simulator doesn't.** `project.yml` reads `DEVELOPMENT_TEAM` from `${OND_DEV_TEAM}`, which XcodeGen substitutes at generate time. Unset, the reference is written through and Xcode resolves it as an undefined setting — no team, which is exactly what a simulator build wants and why a fresh clone needs no Apple ID. A device or archive build does need it; see the release section below.

**Regenerated Swift is committed.** After editing a `.proto`, `mise run generate:proto` rewrites files under `ios/Packages/OndCore/Sources/OndAPI/Generated/`. Commit them; the Xcode build does not run `buf`.

**Postgres 18 moved its data directory.** The compose volume mounts `/var/lib/postgresql`, not `/var/lib/postgresql/data`. Copying a volume line from an older project makes the container refuse to start with a long, easily-misread explanation.

**A StoreKit purchase in the simulator does not reach the server.** Buying Coach against the local `.storekit` configuration convinces the _client_ — `SubscriptionStore` unlocks the Coach tab and every gate reads it from StoreKit — but the transaction it produces is signed by StoreKitTest's per-machine certificate, so `SubmitAppStoreTransaction` rejects it with `grpc_status=3` (`INVALID_ARGUMENT`; the verifier's reason is the chain-shape refusal — `x5c` carries 1 certificate, not Apple's 3-certificate chain to their root) and the server still resolves you to `FREE`. `AssistantService` reads the tier from the row, never from the request, so the coach answers from its rules while doing exactly what it says. The app now tells you: the log line is `the server refused a locally signed transaction, as it must`, and the coach screen shows a notice explaining that this build's purchases stay local. If you ever see `the server refused an Apple-signed transaction` instead, stop — that is a real purchase not being honoured, and it has never been observed. Whether a genuine Apple-signed transaction verifies end to end has **not** been demonstrated: it needs the products to exist in App Store Connect (TIM-62) and one sandbox purchase on a real device, and that single purchase settles it — the log line above answers loudly either way. `mise run dev:coach` writes what a real purchase would have.
