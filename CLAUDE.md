# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. Global workflow and core principles are in `~/.claude/CLAUDE.md`.

## 1. Guiding Principles

1. **Types**: Code must be strongly typed. Avoid `any`, `as`, force-unwraps, and other type-safety escape hatches. Inferred types are acceptable within function bodies; function signatures and complex types are explicit.
2. **Comments**: Default to no comment. Prefer a clear name, type, small function, or test.
   - Add a comment only for a non-obvious contract, invariant, external constraint, failure mode, or deliberately unusual implementation. Put it beside the code it governs. Do not document every public item.
   - Do not restate code, or narrate layout, edits, plans, chats, milestones, or issue tickets. Section banners (`// ── Types ──`, `// ==== Helpers ====`) are banned: nothing enforces the layout they assert, and an editor working 200 lines below never has them in context. A stable domain, specification, or control ID is allowed only when a maintained document defines it.
   - Keep each prose block within five content lines and 400 characters. A blank separator line inside the block counts as a line. Move longer explanations to `docs/` and link to them.
   - The cap binds new and edited comments. Blocks that predate it are waived in `crates/toolkit/comment-length-baseline.tsv`, which keys on path and content — so editing one, or moving the file it lives in, drops its waiver, and the change must bring the block under the cap and delete its row. A repair that only corrects a fact inside such a block, such as a moved path, may instead keep its place by regenerating the row with `mise run comments:baseline`.
   - Use ASD-STE100 Simplified Technical English. State one literal idea per sentence. Use active voice. Do not use metaphors. Assume the reader knows the codebase.
   - Use camel case for abbreviations in identifiers and type names: `Did`, not `DID`; `TechniqueId`, not `TechniqueID`. Prose keeps the natural form — "the technique's ID".
   - Never commit commented-out code. Git already holds that history.
   - Update or delete a comment when its condition changes. Preserve `SAFETY:`, unresolved `TODO`/`FIXME`, and tool directives (`#[allow(...)]` justifications, `swiftlint:disable`, `swiftformat:disable`) unless their underlying condition changes.

   `mise run check` enforces the mechanical rules through `check:comments`. Review decides whether a comment is necessary.

3. **Ergonomics and DX**: Prioritise intuitive API design and developer experience.
4. **Minimal Environment Footprint**: Environment variables are for secrets and essential boot-time context only. The backend reads exactly two — `OND_ENV` and `DATABASE_URL`. Everything else is derived in `crates/api/src/config.rs` — including which provider, region, and model the assistant calls, because a model id that could differ between a laptop and a deployment is exactly the drift this rule exists to prevent. There is no provider key: the assistant signs its Bedrock calls with the EC2 instance profile, which the AWS SDK finds through its default credential chain without being told, and where that chain resolves to nothing the assistant answers from its rule-based fallback. Every new variable is a value that can differ between the two without anything noticing.
5. **Derivation by Convention**: Ports, log format, and CORS policy derive from `OND_ENV`. Prefer deriving over configuring.
6. **Code Structure**: Follow [docs/code-structure.md](docs/code-structure.md) — feature-first (not layer-first), three-tier escalation, and the naming conventions defined there.

## 2. Architecture

A Cargo workspace (`crates/`) and two native SwiftUI apps plus a Live Activity extension (`ios/`) sharing one Protobuf contract (`proto/`). PostgreSQL is the only datastore. Both clients talk **gRPC-Web** to a tonic backend; a small JSON surface (`/health`, `/about`) exists for `curl`.

```text
proto/          the contract — single source of truth for both languages
crates/api      axum + tonic on the app port; Prometheus on a private port
crates/migrate  schema migrations + the seeded technique catalogue
crates/physiology  shared breathing-safety facts used by api and migrate
crates/toolkit   repository tooling behind mise tasks
ios/            Ond (iOS), OndWatch (watchOS), and OndActivity over one local
                SwiftPM package, OndCore; OndKit bundles catalogue.json, the
                seed exported from crates/migrate that both apps breathe
                before they have ever reached the server
web/            the marketing one-pager; static at serve time, but its
                technique figures are generated from the app's own geometry
infra/          OpenTofu for the one box the whole thing deploys onto
```

All önd ports live in **18100–18199**, starting with the API on 18100. [docs/contributing.md](docs/contributing.md) has the table and why the block starts there — one enumeration, so a service added to one list cannot be missing from the other.

| Pattern        | One-liner                                                                                               | Details                                          |
| :------------- | :------------------------------------------------------------------------------------------------------ | :----------------------------------------------- |
| Transport      | One `.proto` generates Rust server stubs and the Swift client; gRPC-Web over HTTP POST                  | [docs/transport.md](docs/transport.md)           |
| Code structure | Feature-first, three-tier escalation, no junk drawers                                                   | [docs/code-structure.md](docs/code-structure.md) |
| Testing        | Write tests. Not too many. Mostly integration.                                                          | [docs/testing.md](docs/testing.md)               |
| Observability  | Log at boundaries, stay silent in between                                                               | [docs/observability.md](docs/observability.md)   |
| Voice          | Spoken cues render at build time; the manifest is the source                                            | [docs/voice.md](docs/voice.md)                   |
| Setup & ports  | First run, port table, Xcode prerequisites                                                              | [docs/contributing.md](docs/contributing.md)     |
| Deployment     | One box: OpenTofu provisions it, `mise run deploy:api` and `deploy:website` ship to it, Caddy fronts it | [docs/deployment.md](docs/deployment.md)         |

### Where code lives

- **Router assembly** — `crates/api/src/lib.rs`. `main.rs` is process startup only; everything else is library so `tests/e2e/` drives the same stack a deployment serves.
- **AppState** — `crates/api/src/state.rs`, shared as `Arc<AppState>`.
- **Features** — `crates/api/src/features/<name>/` with `handlers/`, `service.rs`, `repository.rs`, `types.rs`, `errors.rs`.
- **gRPC registration** — `crates/api/src/grpc.rs`. **HTTP routes** — `crates/api/src/http/mod.rs`. Both are single aggregation points.
- **Generated protobuf** — Rust into `OUT_DIR` via `crates/api/build.rs`, re-exported through `crates/api/src/proto.rs`; Swift committed under `ios/Packages/OndCore/Sources/OndAPI/Generated/`.
- **Domain models (Swift)** — the `OndKit` target in `ios/Packages/OndCore/`. Only it touches generated protobuf types; `OndAPI` is not a package product, so neither app target can import one.
- **Shipping Swift targets** — `ios/Ond/` (iOS), `ios/OndWatch/` (watchOS), and `ios/OndActivity/` (the Live Activity extension), each over the same three package products. What they share and what they deliberately duplicate is in [docs/code-structure.md](docs/code-structure.md).

## 3. Development

**Mise-first rule**: run every repo operation through `mise run <task>` — never raw `cargo clippy/test/sqlx`, `buf generate`, `xcodebuild`, or `swiftlint`. The tasks encode the env (`SQLX_OFFLINE`, `DATABASE_URL`, `CARGO_TARGET_DIR`) those commands need to behave identically here, in a fresh clone, and in CI. `mise tasks` lists everything; if an operation has no task, add one rather than bypassing.

This rule has teeth: a shell that has visited the sibling `connect` repo exports a `DATABASE_URL` pointing at _its_ database on port 15432. Running `cargo run -p migrate` directly from such a shell targets the wrong cluster. `mise run migrate` cannot.

**Toolkit-first rule**: helper tooling is a mise task or a subcommand of `crates/toolkit` — never a loose bash/python script. `scripts/` does not exist and should stay that way.

| Intent                                     | Task                                                  |
| :----------------------------------------- | :---------------------------------------------------- |
| Full validation (the gate)                 | `mise run check`                                      |
| Auto-fix formatting + lint                 | `mise run fix`                                        |
| Rebuild the comment-length waiver ledger   | `mise run comments:baseline`                          |
| Regenerate every derived artefact          | `mise run generate`                                   |
| Start Postgres                             | `mise run dev:db`                                     |
| Apply migrations + seed                    | `mise run migrate`                                    |
| Run the API with reload                    | `mise run dev`                                        |
| Query the database                         | `echo 'select …;' \| mise run db:psql`                |
| Rebuild the DB from scratch                | `mise run dev:db:reset`                               |
| Generate + open the Xcode project          | `mise run ios:gen` / `mise run ios:open`              |
| Build, run on a simulator, run on hardware | `mise run ios:{build,sim,device}:{phone,watch}`       |
| Tests                                      | `mise run test` (`test:rs`, `test:e2e`, `test:swift`) |
| Live backend + iPhone UI system tests      | `mise run test:system`                                |
| Informational Rust + Swift coverage        | `mise run coverage`                                   |

**Before committing** — three commands, in this order:

```bash
mise run generate   # 1. Protobuf, catalogue export, site figures, SQLx cache
mise run fmt        # 2. Format
mise run check      # 3. Full validation
```

`mise run check` runs `check:swift` and `test:swift` through `check:mac`, which detects the Swift toolchain and skips loudly where there is none — so a headless environment still passes the gate without pretending it validated the Swift.

`check:diagrams` stays outside the gate even so, because it builds `OndDiagrams` to redraw the marketing site's figures from the app's own geometry — minutes rather than seconds, and it only has an opinion when `ios/` or `web/` changed. Run it whenever you touch either; without it the page keeps drawing a technique the app has since changed. Nothing else will catch that at the moment: GitHub Actions has been disabled since 2026-08-07, so `mise run check` on your own machine is the whole of the evidence. See [docs/contributing.md](docs/contributing.md) for what re-enabling it needs.

### Commit messages

`<prefix>: <description>`, where the prefix names the area, the feature, or the kind of change, and the description says what changed in the imperative.

The prefix is a hint for someone scanning `git log`, not a taxonomy. `technique:`, `ios:`, `proto:`, `migrate:`, `docs:`, `ci:`, `deps:` are all fine, and so is a conventional-commit type like `fix:` or `refactor:` when the _kind_ of change is more useful than the area. No `(scope)` brackets, no fixed vocabulary, nothing enforcing it — this is a convention because a log that reads consistently is faster to scan, not because a tool parses it.

Keep the subject under ~72 characters. The body is for _why_: the constraint that forced the approach, the alternative rejected, the regression it guards. Git already records what changed; it cannot reconstruct the reasoning.

### Testing

Philosophy and patterns in [docs/testing.md](docs/testing.md).

- **Rust unit** — inline `#[cfg(test)] mod tests` at the bottom of the file under test. Runner is cargo-nextest via `mise run test:rs`, which is scoped to lib and bin targets so it needs no database.
- **Rust integration** — `crates/api/tests/e2e/`, via `mise run test:e2e`. Drives the production router over a disposable `ond_test_<name>_<run stamp>` database, one per test and isolated per run, using real gRPC-Web framing. Never point these at the dev database; the harness makes that structurally impossible and it should stay that way.
- **Swift** — Swift Testing, in `ios/Packages/OndCore/Tests/`. Runs on the host (the package declares a macOS platform for exactly this reason), so no simulator is needed.
