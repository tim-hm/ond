# Observability

## Guiding principle

**Log at boundaries, stay silent in between.**

A line belongs where the error stops. Code that returns a typed error says nothing about it — the boundary that catches one has the context and decides whether it is worth a line, and a repository that logs its own failure _and_ returns it produces two records of one event. In practice that means handlers and the `From<…> for Status` impls speak while `service.rs` and `repository.rs` stay quiet, with one exception the named patterns below make explicit: a layer that swallows an error rather than returning it _is_ the boundary for that error.

## Levels

Keyed on a single question: _was this expected?_

| Level   | Means                                                    | Example                                                |
| :------ | :------------------------------------------------------- | :----------------------------------------------------- |
| `error` | Unexpected. Something is broken and a human should look. | A query failed against a schema that should support it |
| `warn`  | A handled failure mode. Degraded but understood.         | A dependency was unreachable and the fallback ran      |
| `info`  | A lifecycle milestone. Rare, and permanent.              | "connected to the database", "listening"               |
| `debug` | Detail for an investigation in progress                  | A connection retry attempt                             |
| `trace` | Per-request hot path                                     |                                                        |

The test for `info`: would you still want this line after a million requests? "listening" yes; a handler announcing that it is about to do its job, no.

One record per request is the exception, and it earns the level because it is the only thing that answers "what was this process doing at 14:03". It is emitted once, when the response head leaves, by the `TraceLayer` in `crates/api/src/obs/trace.rs` — carrying `status`, `grpc_status` and `duration_ms` against a span holding `method`, `path` and `user_id`. Everything else inherits that span, which is what makes a feature's one-line `error` resolvable to a caller and an RPC. A streaming RPC's final native status lives in its trailers, after this access record; the native gRPC metrics below wrap the body to observe that completion without holding the response back. Note that a span emits nothing by itself: the layer was installed for a long time at a level the default filter dropped, and the process was silent per request the whole while.

## Field conventions

- `error`, never `err`.
- `duration_ms` for elapsed time, `status` for HTTP status codes.
- Values that are enums or IDs are recorded via Display: `goal = %goal`.
- The message is a short lowercase phrase, not a sentence: `"connected to the database"`.

## Named patterns

**Log before converting.** Each feature's error enum logs server-side faults in its `From<…> for tonic::Status` impl, at the point of conversion — `crates/api/src/features/technique/errors.rs` is the pattern. The client receives an opaque `internal` status, so a conversion that stays silent leaves the failure unreproducible from outside the process. The sqlx error is deliberately _not_ forwarded to the client — it can carry table and column names — and the log is where that detail belongs.

**Log what you swallow.** `crates/api/src/features/assistant/service.rs` is the service allowed to speak, and the reason is that its errors terminate there: a model call that fails, a reply naming no technique in the catalogue, and a spent daily allowance all end in the rule-based fallback, and the RPC returns a perfectly good answer. Nothing downstream is ever told, so deleting those lines makes a provider outage invisible from outside the process — the same failure log-before-converting prevents, reached from the other direction.

**Audit the irreversible.** A service may log a destructive or ownership-moving outcome at `info` when the response cannot carry the fact and nothing further out can reconstruct it. Three lines qualify today, on two grounds. Either the record needs two ids the layers above never hold together — the entitlement transfer names the displaced holder beside the claimant, the identity merge names the row that ceased to exist beside the one that absorbed it — or the subject stops existing, which is why the account erasure carries no id at all: `identity::resolve` has already put the caller on the span, and what was erased is by definition not something to write down. The handler above sees an ordinary success in every case, so the boundary rule would leave no record of the destructive thing the server just did on a client's say-so. The bar is deliberately high: irreversible, rare enough to still be worth reading after a million requests, and unrecoverable from anywhere else. A milestone that merely _sounds_ important is still the handler announcing its job.

**Correlation ID.** When an HTTP handler returns a failure to a caller, mint a `cuid2`, log it alongside the cause, and return it in the body as `request_id`. A user-reported failure then resolves to one log line instead of a timestamp and a guess. No handler needs this yet — `/health` and `/about` are infallible — so the helper does not exist. Write it with the first fallible route rather than in advance.

**Level escalation.** A retry loop logs each attempt at `debug` and only the final failure at `warn` or `error`. No hand-written retry loop exists yet — `crates/migrate/src/main.rs` deliberately leans on sqlx's pool backoff instead — but the first one should follow this shape: a slow Postgres boot is normal, and ten `warn` lines for a situation that resolved itself trains people to ignore warnings.

## Format

JSON in production, human-readable in dev — chosen once at boot in `crates/api/src/obs/trace.rs` from `OND_ENV`. JSON is unreadable in a terminal and mandatory in a log aggregator, and `Environment` already knows which one is reading.

`RUST_LOG` overrides the filter; the default is `api=info,tower_http=info,warn`.

## The Swift client

The principle above carries over unchanged. `os.Logger` does not: four of its properties decide whether a line survives to be read at all, and each has caught this codebase out.

**One subsystem: `xyz.holmie.ond`,** taken from a single constant in `OndKit` rather than a literal or a `Bundle.main.bundleIdentifier` lookup. `Bundle.main` is the _host process_, so the same `OndKit` file files under one subsystem when the phone loads it and another when the watch does — and `log stream --subsystem xyz.holmie.ond` then silently omits the watch, the target whose failures are hardest to reproduce. A subsystem that varies by host is not a subsystem.

**A category names the channel, not the file.** Both ends of the phone↔watch handoff take `watch-link`, so correlating a dropped identity means one name rather than two. The set today:

| Category           | Covers                                                                   |
| :----------------- | :----------------------------------------------------------------------- |
| `identity`         | The anonymous id — Keychain reads and writes, and the watch adopting one |
| `account`          | Signing in with Apple, and erasing the account and this device with it   |
| `profile`          | Onboarding's answers syncing out and restoring back                      |
| `session-store`    | The local session and tombstone files                                    |
| `bolt-store`       | The local controlled-pause file                                          |
| `journey-sync`     | Sessions, tombstones, and pause scores draining to the server            |
| `catalogue-cache`  | The offline catalogue's reads and writes                                 |
| `catalogue-export` | The seeded catalogue this build ships with, read out of the bundle       |
| `user-technique`   | The exercises somebody composed — loading them, saving one, deleting one |
| `leaderboard`      | The one screen that needs a connection, and what it does without one     |
| `assistant`        | Guidance and explanations, including a stream the provider cut short     |
| `subscription`     | StoreKit purchases and restores, and the entitlement the server stores   |
| `schedules`        | Practice reminders: the notification grant, and a request iOS refused    |
| `health`           | The mindful session written back to Health after a session ends          |
| `watch-link`       | The handoff, from both ends                                              |
| `haptics`, `audio` | The session's cue engines                                                |
| `extended-runtime` | The watch's grant to keep running with the wrist down                    |
| `live-activity`    | The session's presence on the lock screen — a request the system refused |
| `discreet-spike`   | A `DEBUG`-only harness on the watch; see the note below the table        |

`discreet-spike` is the one channel not carrying a failure. It is a `#if DEBUG` instrument that measures whether a half-hour extended runtime session survives on a real wrist, and its `notice` level is deliberate: the readings are worth nothing unless they can be collected off the device hours later, which is exactly what persistence buys. It stays inside the budget below by writing one line per burst — up to thirteen minutes apart — rather than one per cue, and it ships in no release build.

**Levels answer the same question — _was this expected?_** — against a second constraint the backend does not have: `notice` and above are written to the on-disk log store, which is what a sysdiagnose collects and which has a fixed size budget.

| Level    | Means                                                  | Example                                               |
| :------- | :----------------------------------------------------- | :---------------------------------------------------- |
| `error`  | Broken, and nothing recovers it                        | The Keychain refused to store the anonymous identity  |
| `notice` | A handled degradation. Offline-first behaviour working | A sync deferred, or a cache that could not be written |
| `debug`  | Detail for an investigation in progress                | A per-cue scheduling decision                         |

So anything per-frame, per-detent, or per-cue is `debug`, whatever it would otherwise deserve: a persisted line on a drag gesture evicts the sync and identity failures that were the reason to keep a log store at all.

**The model writes the record; the view only shows it.** The boundary rule above reads differently against SwiftUI, because a view catching an error does not keep it: it renders the cause beside the field and drops it with the sheet, and the next screen calling the same write would need its own copy of the line. So where a model rethrows for a view to render — `UserTechniqueModel.save` and `delete` are the two — the model logs on the way past and the views stay silent. One failure is still one line, and it does not have to be re-added for each screen that saves. A model that swallows the error instead (`load`, `AccountModel.signIn`) is the ordinary case and speaks for the ordinary reason.

**Framework error text is public; the person's words never are.** Interpolation defaults to `.private` for `String`, and `error.localizedDescription` is a `String` — so a line reads `<private>` everywhere except a live debugger, which is the one place it was not needed. Framework-authored text carries no user data, so it takes the annotation explicitly:

```swift
logger.notice("session sync deferred: \(error.localizedDescription, privacy: .public)")
```

The display name and the intent note never do. They are the person's own words, and unlike the backend's anonymous `user_id` there is nothing anonymous about them.

## Metrics

**Two kinds of number, and only one of them is about the server.** Request rate, status and latency say whether the box is healthy. The census — how many people exist, how many are paying, what that bills in a month — says whether the product is working, which is the question the dashboard was built to answer. A box nobody is paying for is up in exactly the same way as one everybody is.

Served on **18103, a separate listener from the public 18100** (`api::metrics_router`, bound in `main.rs`). The reason is exposure rather than tidiness: as a path on the main router it would be private only for as long as the Caddyfile's `@api` matcher stayed an allowlist, and that is a reasonable-looking edit away from publishing the census. The api service maps no host port, so the only things that can reach 18103 are the containers beside it.

| Metric                              | Kind      | Says                                                            |
| :---------------------------------- | :-------- | :-------------------------------------------------------------- |
| `ond_users_total`                   | gauge     | Every identity ever created — one per first launch, not signups |
| `ond_active_subscriptions`          | gauge     | Live subscriptions, labelled `tier`                             |
| `ond_gross_mrr_usd`                 | gauge     | Those subscriptions at US list price. Not money received        |
| `ond_requests_total`                | counter   | JSON and transport outcomes, labelled `route` and HTTP `status` |
| `ond_request_duration_seconds`      | histogram | JSON and transport latency, labelled `route`                    |
| `ond_grpc_requests_total`           | counter   | Completed native calls, labelled by numeric gRPC `status`       |
| `ond_grpc_request_duration_seconds` | histogram | Native call completion latency, labelled by gRPC `status`       |

**Every label comes from a closed set.** HTTP `route` is `/health`, `/about`, `grpc_transport`, or `other`; it excludes HTTP-200 gRPC envelopes because their native outcome is recorded once by the gRPC families. A label taken straight from the URI lets anything that can reach this server mint a time series per request, so scanner paths collapse to `other` and pre-envelope gRPC failures to `grpc_transport`. The native status label is likewise restricted to gRPC's numeric codes 0–16; malformed or missing final statuses become `Unknown` (2), including a body that fails or ends without trailers.

**The census is derived on demand, then reused for one minute.** The single-flight cache lets four ordinary fifteen-second scrapes share one population scan, while concurrent misses share one refresh. There is no background lifecycle and the dashboard reacts on a human timescale without repeatedly counting the entire `users` table.

**A database that stops answering reports `NaN`, not the last good reading.** A gauge that keeps serving a number it can no longer verify makes the dashboard look healthiest exactly when Postgres has stopped answering.

**Who counts as subscribed is defined once**, in `features::entitlement`, whose metrics handler owns the census cache, query and product labels. `obs::metrics` owns only recorder and transport mechanics. The tempting alternative — custom SQL in the Postgres exporter's config — puts a second definition of _paying_ somewhere no test in this workspace can reach, free to disagree with the gate the app actually enforces. The exporter is therefore left to Postgres' own internals.

## The dashboard

Grafana on the box, reachable **only over the tailnet**: the container publishes 3000 on loopback and `tailscale serve` proxies it at the node's own MagicDNS name on **port 18104**, with TLS from a certificate Tailscale issues. The port is not cosmetic — `serve`'s default of 443 collides with Caddy's, and [deployment.md](deployment.md) records what that outage looks like. No security group rule admits it and none is asked for; the tailnet ACL is the whole of the authorisation, which is the same rule that admits an SSH session (see [deployment.md](deployment.md)).

Grafana runs with **anonymous access and no login form**, which is only correct while that port stays on loopback. Publishing it anywhere else makes the dashboard world-writable.

The datasource and the dashboards are **provisioned from `infra/box/grafana/`**, so a panel edited in the browser is temporary by design — the file wins at the next restart, and a dashboard worth keeping is a commit.

## Not yet present

No tracing export, no error reporting.
