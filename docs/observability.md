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

A monitor's _successful_ probe is the exception to the exception, and only the level moves — the record is still emitted exactly once per request. `/health` and `/metrics` carry theirs at `debug` on the `api::probe` target, which the default filter drops. They are the only two paths anything asks for on a timer, and between them they were most of this process's log volume: Route 53 probes `/health` every 30s from roughly fifteen global checkers and Prometheus scrapes `/metrics` every 15s, on the order of two thousand identical `status=200` lines an hour before the server had answered a single person. That is the `info` test above applied to the request record itself. A probe answering anything other than 2xx stays at `info`, because a check that has started failing is the one you were watching for — which is also why the level cannot be keyed on the route alone. Nothing is lost by the demotion: `ond_requests_total{route="/health"}` still counts every probe, and `up` / `TargetDown` already answer "did the scrape happen" for `/metrics`. The mechanism is worth knowing before reordering `build_app`: `OnResponse` is handed the response and not the request, so a marker layer sitting directly beneath the `TraceLayer` stamps the response and the layer above reads it. Anything inserted between those two could rebuild the response, drop the marker, and silently restore the noise.

**The Bedrock call is the other per-request `info`.** A completed non-streaming provider call writes one line carrying the model, `duration_ms` and its token counts. Every number in it is already a metric; what the line adds is _which caller_ the spend belongs to, through the request span, and no counter can give that. It is not the only other `info` a request can write — the three audit lines below are — but those are rare by design and this one fires on every completed call. It is affordable while the daily allowance bounds the volume, so the expiry condition is that allowance ceasing to bound it: raise the cap, or reach a traffic level where the coach answers continuously, and this line demotes to `debug` with `ond_assistant_tokens_total` left carrying the total.

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

**A deploy's migration step decides this a second time.** `crates/migrate/src/main.rs` installs its own subscriber, defaulting to `migrate=info,warn` and picking JSON by comparing `OND_ENV` against the literal `"production"`. The API matches on `Environment` instead, so a new environment name is a compile error there and silent unparsed text here — in the one step whose failure a deploy has to read. The fix is a leaf crate both can depend on, the way `crates/physiology` already works.

To watch probe traffic during an incident, `RUST_LOG=api=info,api::probe=debug` — the demoted access records have a target of their own precisely so that reading them does not also turn on every other `debug!` in the crate.

One `warn` in the stream is not ours to write and is worth recognising on sight: sqlx emits a slow-statement record on target `sqlx::query`, carrying the SQL, and the trailing `warn` in the default filter admits it. It is deliberately kept — it is the only thing that reports a query degrading while it is still succeeding, where `ond_request_duration_seconds` shows the request slowing without naming what slowed it. The threshold is set in `crates/api/src/main.rs` beside `statement_timeout` rather than inherited from sqlx, because a default that changes on a dependency bump changes production log volume with nobody having decided to.

## The Swift client

The principle above carries over unchanged. `os.Logger` does not: four of its properties decide whether a line survives to be read at all, and each has caught this codebase out.

**One subsystem: `xyz.holmie.ond`,** taken from a single constant in `OndKit` rather than a literal or a `Bundle.main.bundleIdentifier` lookup. `Bundle.main` is the _host process_, so the same `OndKit` file files under one subsystem when the phone loads it and another when the watch does — and `log stream --subsystem xyz.holmie.ond` then silently omits the watch, the target whose failures are hardest to reproduce. A subsystem that varies by host is not a subsystem.

**A category names the channel, not the file.** Both ends of the phone↔watch handoff take `watch-link`, so correlating a dropped identity means one name rather than two. `Log.categories` is the executable registry; `mise run check:observability` keeps every active production literal and the operator-facing descriptions below equal to it while excluding generated, test and development-only Swift.

| Category             | Covers                                                                   |
| :------------------- | :----------------------------------------------------------------------- |
| `account`            | Signing in with Apple, and erasing the account and this device with it   |
| `assistant`          | Guidance and explanations, including a stream the provider cut short     |
| `audio`              | Spoken and tonal session cues                                            |
| `bolt-store`         | The local controlled-pause file                                          |
| `catalogue-export`   | The seeded catalogue this build ships with, read out of the bundle       |
| `chat-store`         | Coach conversation history stored on the device                          |
| `haptics`            | The phone session's tactile cue engine                                   |
| `health`             | HealthKit reads and mindful-session writes                               |
| `home`               | Home-screen preferences stored on the device                             |
| `identity`           | The anonymous id — Keychain reads and writes, and the watch adopting one |
| `journey-sync`       | Sessions, tombstones, and pause scores draining to the server            |
| `leaderboard`        | The one screen that needs a connection, and what it does without one     |
| `live-activity`      | The session's presence on the lock screen — a request the system refused |
| `profile`            | Onboarding's answers syncing out and restoring back                      |
| `reference-cache`    | Offline technique, route and foundation data                             |
| `resting-rate-store` | The local resting-breath-rate file                                       |
| `safety`             | Safety consent and accepted exercise warnings                            |
| `schedules`          | Practice reminders: the notification grant, and a request iOS refused    |
| `session-runtime`    | Watch runtime budgets and pulse sharing with the phone                   |
| `session-store`      | The local session and tombstone files                                    |
| `settings`           | Per-technique session overrides stored on the device                     |
| `subscription`       | StoreKit purchases and restores, and the entitlement the server stores   |
| `user-technique`     | The exercises somebody composed — loading them, saving one, deleting one |
| `voice-clips`        | Shipped cue audio discovered in the app bundle                           |
| `watch-link`         | The handoff, from both ends                                              |

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

Served on **29103, a separate listener from the public 29100** (`api::metrics_router`, bound in `main.rs`). The reason is exposure rather than tidiness: `api.ondbreathe.app` reverse-proxies every path to 29100 unconditionally, so a metrics route on the main router would be a public metrics route the moment it was added — there is no path allowlist left to keep it private. The separate port is what makes that structural instead of conventional. The api service maps no host port, so the only things that can reach 29103 are the containers beside it.

| Metric                                      | Kind      | Says                                                                                                               |
| :------------------------------------------ | :-------- | :----------------------------------------------------------------------------------------------------------------- |
| `ond_users_total`                           | gauge     | Every identity ever created — one per first launch, not signups                                                    |
| `ond_active_subscriptions`                  | gauge     | Live subscriptions, labelled `tier`                                                                                |
| `ond_gross_mrr_usd`                         | gauge     | Those subscriptions at US list price. Not money received                                                           |
| `ond_requests_total`                        | counter   | JSON and transport outcomes, labelled `route` and HTTP `status`                                                    |
| `ond_request_duration_seconds`              | histogram | JSON and transport latency, labelled `route`                                                                       |
| `ond_grpc_requests_total`                   | counter   | Completed native calls, labelled `method` and numeric `status`                                                     |
| `ond_grpc_request_duration_seconds`         | histogram | Native call latency, labelled `method`                                                                             |
| `ond_assistant_answers_total`               | counter   | Who wrote the reply, labelled `source` — `model` or `fallback`                                                     |
| `ond_assistant_fallbacks_total`             | counter   | Why the rules answered, labelled `reason`                                                                          |
| `ond_assistant_tokens_total`                | counter   | What the coach cost — `kind` is `prompt`, `completion`, `cached` or `cache_write`, priced differently and disjoint |
| `ond_assistant_call_duration_seconds`       | histogram | A completed non-streaming provider call                                                                            |
| `ond_assistant_time_to_first_token_seconds` | histogram | How long somebody waits before the coach starts writing                                                            |
| `ond_assistant_mode`                        | gauge     | Where a reply would come from, as a state set over `mode`                                                          |
| `ond_entitlement_verifications_total`       | counter   | What became of an entitlement decision, labelled `outcome`. Two outcomes are not purchases — see below             |
| `ond_entitlement_rejections_total`          | counter   | Why one was rejected, labelled `reason` — the breakdown that makes the alert diagnosable                           |
| `ond_entitlement_purchases_total`           | counter   | Honoured purchases, labelled `environment`. A revocation is not one                                                |
| `ond_identities_created_total`              | counter   | First sightings — the rate `ond_users_total` cannot give                                                           |
| `ond_sign_ins_total`                        | counter   | Completed sign-ins, labelled `outcome` — `claimed`, `resumed` or `merged`                                          |
| `ond_db_pool_connections`                   | gauge     | Pool occupancy, labelled `state` — `idle` or `in_use`                                                              |
| `ond_panics_total`                          | counter   | Tasks that panicked. Hyper unwinds the connection and carries on                                                   |
| `ond_build_info`                            | gauge     | Always 1; the labels say which build is answering                                                                  |
| `ond_process_start_time_seconds`            | gauge     | When this process started. A step here is a deploy                                                                 |
| `ond_backup_last_success_timestamp_seconds` | gauge     | When a dump was last verified and uploaded                                                                         |
| `ond_backup_last_attempt_timestamp_seconds` | gauge     | When the backup last ran, whatever came of it. A stale one says cron stopped firing, which no other metric says    |
| `ond_backup_success`                        | gauge     | Whether the most recent attempt produced a restorable dump                                                         |
| `ond_backup_bytes` / `_duration_seconds`    | gauge     | Size and runtime of that dump                                                                                      |

The last four are written by `infra/box/backup.sh` into node-exporter's textfile collector rather than by this process, and they are metrics all the same — a rule cannot tell the difference and should not have to.

**Two of the seven entitlement outcomes are not purchases.** `unentitled` is recorded whenever any gated RPC refuses a free caller, and `faulted` on a database error during any entitlement read. Neither involves a submitted transaction, and `unentitled` is by a long way the largest series of the seven. `PurchasesBeingRejected` divides by `rejected|honoured` alone for that reason, and the Money row's "Purchase outcomes" panel leaves the same two out — a wider slice than the alert, but still only the outcomes a purchase can reach.

**Every label comes from a closed set.** HTTP `route` is `/health`, `/about`, `grpc_transport`, or `other`; it excludes HTTP-200 gRPC envelopes because their native outcome is recorded once by the gRPC families. A label taken straight from the URI lets anything that can reach this server mint a time series per request, so scanner paths collapse to `other` and pre-envelope gRPC failures to `grpc_transport`. The native status label is likewise restricted to gRPC's numeric codes 0–16; malformed or missing final statuses become `Unknown` (2), including a body that fails or ends without trailers.

**`method` is read out of the protobuf descriptor set**, the same one `grpc.rs` registers for reflection — never a hand-kept list. A second copy of the contract fails silently: an RPC added to the `.proto` and not to the list records as `other`, and the metric goes on looking healthy while the call it cannot name is the one failing. Anything outside the contract collapses to `other`, which is what bounds the label.

**Counters carry the outcome; histograms carry the operation.** Both transport families follow it and it is worth stating, because the obvious alternative is the expensive one: a histogram is a series per bucket, so labelling it with the status as well multiplies the RPC count by seventeen codes and again by the bucket count — to answer how slowly a call failed, which nobody asks. What is wanted is which call is slow and which call is failing, and that is one label each.

**`mise run check:metrics` asserts every name the dashboard, the rules and this table use is one something emits.** A renamed metric is silent in the worst direction: the panel reading it goes blank, which looks like a quiet system, and the alert on it becomes structurally incapable of firing, which looks like health.

**The census is derived on demand, then reused for one minute.** The single-flight cache lets four ordinary fifteen-second scrapes share one population scan, while concurrent misses share one refresh. There is no background lifecycle and the dashboard reacts on a human timescale without repeatedly counting the entire `users` table.

**A database that stops answering reports `NaN`, not the last good reading.** A gauge that keeps serving a number it can no longer verify makes the dashboard look healthiest exactly when Postgres has stopped answering.

**Who counts as subscribed is defined once**, in `features::entitlement`, whose metrics handler owns the census cache, query and product labels. `obs::metrics` owns only recorder and transport mechanics. The tempting alternative — custom SQL in the Postgres exporter's config — puts a second definition of _paying_ somewhere no test in this workspace can reach, free to disagree with the gate the app actually enforces. The exporter is therefore left to Postgres' own internals.

## The dashboard

Grafana on the box, reachable **only over the tailnet**: the container publishes 3000 on loopback and `tailscale serve` proxies it at the node's own MagicDNS name on **port 29104**, with TLS from a certificate Tailscale issues. The port is not cosmetic — `serve`'s default of 443 collides with Caddy's, and [deployment.md](deployment.md) records what that outage looks like. No security group rule admits it and none is asked for; the tailnet ACL is the whole of the authorisation, which is the same rule that admits an SSH session (see [deployment.md](deployment.md)).

Grafana runs with **anonymous access and no login form**, which is only correct while that port stays on loopback. Publishing it anywhere else makes the dashboard world-writable.

The datasource and the dashboards are **provisioned from `infra/box/grafana/`**, so a panel edited in the browser is temporary by design — the file wins at the next restart, and a dashboard worth keeping is a commit.

Seven rows, in the order somebody actually reads them: **Now** (the census, targets down, the coach's mode, and a list of firing alerts), **Traffic** (calls, failures and latency per RPC, outcomes by status code, and edge latency), **Coach** (where answers come from, why it fell back, time to first token, tokens, provider call latency), **Money** (purchase outcomes, why one was rejected, and the sandbox/production split), **The box** (both disks, memory, CPU, the pool, database size, backup age, whether the last backup verified, the edge, Postgres connections), **Logs**, and **Product** (people and MRR over time, new identities and sign-ins per day).

Two details are load-bearing. The firing-alerts panel reads Prometheus' own `ALERTS` series rather than Grafana's `alertlist` panel, which renders only Grafana-managed rules — these are datasource-managed, so that panel would list nothing for ever. And "targets down" counts `up == 0` rather than comparing against a hard-coded healthy total, which would leave the panel permanently red the day a scrape job is added and green at a wrong number the day one is removed.

**The Logs row is the only place Loki appears in Grafana.** One panel, "Errors", on the `ond-loki` datasource, reading `{host="ond"} |~ "(?i)error"` over every container on the box. It filters the line rather than selecting on a label because only the API emits a `level` — the other containers log plain text, and a label selector would silently drop exactly the containers whose failures nothing else reports.

A **deploy shows as an annotation**, read from `ond_process_start_time_seconds`. Not from `ond_build_info`: that series is always 1 and what a deploy changes is its labels, so `changes()` over its value sees nothing on either side. Every deploy restarts the process, so a step in the start time is a release — and a crash-restart, which is worth marking for the same reason.

## Alerts

`infra/box/alerts.yml`, rsynced to the box with everything else in `infra/box/` and read by Prometheus at startup. `mise run check:alerts` parses them with `promtool` from the same image tag compose runs, because a rule that does not parse stops Prometheus booting — and `restart: unless-stopped` then loops it quietly while the API and Caddy carry on serving. The same task runs `promtool test rules` against `alerts_test.yml`, which is the half that matters: parsing says nothing about whether a rule fires when it should and, more importantly, stays quiet when it should not.

| Alert | Fires when | Why it is not noise |
| :-- | :-- | :-- |
| `TargetDown` | any scrape target is down 2m | Eight scrape intervals, so a deploy's own restart does not reach it |
| `DatabaseUnreachable` | `pg_up == 0` for 2m | `/health` answers without touching Postgres, so nothing else separates a live process from a live database |
| `BackupStale` | no verified dump for 26h | One daily cycle plus slack. The timestamp only moves after a dump is read back and measured |
| `BackupMetricMissing` | the backup has never reported | `BackupStale` cannot fire on a metric that does not exist; this is what notices that |
| `DiskFillingUp` | either volume below 15% free for 30m | A disk crossing a threshold is a trend, so a dump's temp file cannot page anyone on its way past |
| `MemoryLow` | under 15% available for 15m | 2 GiB with no swap: what follows is the OOM killer picking a process, and it will not pick the culprit |
| `GrpcUnexpectedFailures` | >5% of calls fail for 10m, above an absolute floor | Excludes the statuses this API returns on purpose — see below |
| `AssistantFallingBack` | >50% of coach answers come from the rules for 15m | Excludes an unsubscribed caller and a spent allowance, which are the product working |
| `PurchasesBeingRejected` | >50% of submitted purchases rejected for 15m | A share, not a count: one rejection is a sandbox tester, half of them is the money path broken |
| `ProcessPanicked` | any panic | Hyper unwinds the connection and the process survives, so nothing else reports it |
| `ServerErrorsSustained` | any `Internal` for 10m | There is no acceptable rate of the server being wrong |
| `AuthenticationRefusalsSustained` | status 16 above a floor for 15m | The identity path refuses at `debug`, which production drops, so nothing else sees a run guessing credentials |
| `ThrottleRefusalsSustained` | status 8 above a floor for 15m | A caller must spend a whole budget — six hundred requests a minute, or ten new identities — before one exists |

The exclusion in `GrpcUnexpectedFailures` is the load-bearing part. Four codes are ordinary: `16` before an identity settles, `8` from the throttle, `7` from a free caller reaching a paid lever, `3` from a malformed request. Two more, `1` and `2`, are a phone disconnecting. A rule on "not zero" would fire on a working system, which is the failure mode that teaches people to ignore alerts. `alerts_test.yml` drives exactly that traffic and asserts silence.

**Two of those excluded codes get a rule of their own instead**, because being ordinary at a trickle does not make them ordinary at volume. Both read an absolute rate rather than a share: an attack against a busy server would dilute away in a share. Each floor therefore sits above today's honest baseline — a reinstall that kept its id and lost the Keychain returns `16`, and a carrier NAT fills a request budget — and each has to move as real traffic arrives. `alerts_test.yml` drives that baseline and asserts silence, then drives an attack and asserts each fires.

**Three of these exist because a successful response is this server's most common way to fail.** A Bedrock outage returns gRPC 0 with a rule-based answer; a rejected Apple purchase returns gRPC 3, which is excluded above, and logs at `debug`, which production drops; a panicking task leaves a dead connection and a live process. None was visible in the transport metrics, and each needed a metric that names the thing rather than the transport carrying it.

## Delivery

Alertmanager publishes to an SNS topic and one email subscription takes everything. It signs with the instance profile, so no credential lands on the box — the property the assistant's Bedrock calls and the backup's S3 writes already had. `infra/box/alertmanager.yml.tmpl` is rendered by `mise run deploy:api` from the OpenTofu state, because the topic ARN carries the account id and a literal committed beside the config is a literal nothing reconciles.

An email cannot acknowledge anything, so a flapping alert re-notifies every `repeat_interval` (12h). Silences live in Alertmanager's own UI, on the tailnet at **29106**; Prometheus' own UI and `/alerts` page are at **29105**.

**What none of that covers is the case where the rules are never evaluated.** A stopped box, a full disk, or a Prometheus crash-looping on a rule file that does not parse all look exactly like nothing firing. Two things outside the box answer that:

- **Route 53 health checks**, one per public hostname, each with its own alarm into the same SNS topic — `ond-public-unhealthy-api` for `https://api.ondbreathe.app/health`, `ond-public-unhealthy-web` for `https://ondbreathe.app/privacy`. Split because the hostnames are: each has its own certificate and its own Caddy site block, so one probe cannot speak for both. The paths are the fragile part of each — the API's one handler that touches no database, and the extensionless page URL that resolves only through `try_files` and that App Review rejects a paywall over. Both match on the response body rather than the status, because Route 53 does not verify the certificate it is served, so a 200 is not a claim about who answered. The alarms live in **us-east-1**, which is the only region Route 53 publishes those metrics to — an alarm built anywhere else sits in `INSUFFICIENT_DATA` for ever.
- A **dead-man's switch**: `heartbeat.sh` publishes a CloudWatch metric every five minutes while Prometheus _and_ Alertmanager both answer, against an alarm that treats missing data as breaching. Nothing on this box has to be alive for that alarm to fire, which is the entire point.

This is the failure the repository has actually had: `tailscale serve` taking 443 left Caddy running with no network attached, and `docker ps` said up while the site answered nothing (see [deployment.md](deployment.md)). Not one on-box rule can fire on that.

## Logs, after the box

The API has emitted aggregator-ready JSON since its subscriber chose that format, and for a long time nothing aggregated it: fifty megabytes per service of Docker's rotation, read over SSH, gone after a chatty week. An incident heard about on Monday was already unrecoverable.

**Grafana Alloy** reads the containers' json-file logs off disk and pushes them to a single-binary **Loki**, whose chunks live in S3 with a thirty-day retention — the same window as the metrics, so an incident is read with its graphs beside it. The bucket is written with the instance profile, so no credential lands on the box, and logs survive losing the instance, which an on-box store would not.

Two choices are worth knowing. **Alloy rather than Promtail**, which reached end of life earlier this year. And **reading the files rather than replacing the logging driver**: a driver puts the log path inside container startup, and the Loki plugin can block a container from starting when the sink is unreachable — which turns "the aggregator is down" into "the API is down". Reading after the fact cannot, and `docker compose logs` keeps working, which is still the fastest way to see the last few minutes.

Loki's `retention_period` only deletes because the compactor is explicitly enabled; without that the setting reads as honoured and the bucket grows for ever. The bucket's own 35-day lifecycle is the backstop, set past Loki's thirty so it is not racing the compactor.

Both configurations are gated, for the reason `alerts.yml` is: `mise run check:loki` runs Loki's own `-verify-config`, and `mise run check:alloy` runs `alloy validate` rather than `alloy fmt` — `fmt` proves only that the file parses as River, so a misspelled component or a stage nested where it is not allowed formats cleanly and fails at startup instead. A log pipeline that will not boot looks exactly like a box nobody has logged anything on.

Every observability container carries a `mem_limit` and the two that matter, `db` and `api`, deliberately do not. The box has 2 GiB and no swap, so the OOM killer arbitrates by size rather than importance, and Loki compacting is briefly the largest process here — unbounded, the log store getting busy is answered by killing Postgres. The ceilings make the monitoring the first casualty of its own load rather than the last. They are first estimates: tighten them once node-exporter has a few days behind it.

## Not yet present

No tracing export and no error reporting. No client-side crash reporting either, deliberately — `web/privacy.html` promises no third-party analytics or crash SDK, so TestFlight and App Store crashes are read in Xcode Organizer instead.
