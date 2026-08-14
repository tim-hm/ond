# Transport

How a value gets from a Postgres row to a SwiftUI view, and why the pipeline is shaped this way.

## The contract is the source of truth

`proto/ond/v1/` holds the only definition of the API. Nothing else describes it — there is no OpenAPI document, no hand-written Swift model, no shared types package. Two generators read it:

| Target       | Generator                                                        | Output                                               | Committed? |
| :----------- | :--------------------------------------------------------------- | :--------------------------------------------------- | :--------- |
| Rust server  | `tonic-prost-build`, from `crates/api/build.rs`                  | `OUT_DIR`, re-exported via `crates/api/src/proto.rs` | No         |
| Swift client | `buf generate` (`protoc-gen-swift` + `protoc-gen-connect-swift`) | `ios/Packages/OndCore/Sources/OndAPI/Generated/`     | Yes        |

The asymmetry is deliberate. Rust regenerates on every `cargo build`, so a stale artefact is impossible and committing one would only create merge noise. Xcode has no equivalent hook, and requiring `buf` to be installed before the app compiles would put a Go toolchain between a new contributor and their first build — so the Swift output is committed and refreshed by `mise run generate:proto`.

## Why gRPC-Web

The server is tonic wrapped in `tonic_web::GrpcWebLayer` (`crates/api/src/lib.rs`, where the router is assembled — `main.rs` is process startup and nothing else). The client is `connect-swift` configured with `networkProtocol: .grpcWeb` (`ios/Packages/OndCore/Sources/OndAPI/Clients.swift`).

connect-swift speaks three protocols — Connect, gRPC, and gRPC-Web — and the server has to speak the same one:

- **Connect** would be the nicer protocol: plain HTTP with JSON or binary bodies, trivially curl-able. There is no mature Connect-protocol _server_ for Rust, so this would mean writing the protocol adapter by hand.
- **gRPC** proper needs HTTP/2 with trailers. That works, but it puts an HTTP/2-capable path between the app and the server for every proxy that will ever sit in between.
- **gRPC-Web** is a POST with a binary body and the status carried in headers. tonic ships a production layer for it, connect-swift supports it as a first-class client protocol, and it survives ordinary HTTP/1.1 infrastructure.

gRPC-Web is the only option where both ends are maintained by their upstreams and neither side needed code written to bridge them.

**Consequence to remember:** the status lives in the `grpc-status` and `grpc-message` headers. A CORS policy that does not `expose_headers` those two produces a request that succeeds on the wire and fails in the client, with nothing in the server log to suggest why. `cors_layer` in `crates/api/src/lib.rs` exposes them, and that is the only reason it exists.

## One port, two protocols

Both surfaces share a listener:

```rust
let grpc_router = grpc::build_services(&state)?
    .prepare()
    .into_axum_router()
    .layer(axum::middleware::from_fn_with_state(
        Arc::clone(&state),
        identity::resolve,
    ))
    .layer(axum::middleware::from_fn_with_state(
        Arc::clone(&state),
        throttle::enforce,
    ))
    .layer(tonic_web::GrpcWebLayer::new());

Ok(http::router(state)
    .fallback_service(grpc_router)
    .layer(cors)
    .layer(obs::trace_layer()))
```

gRPC paths are `/ond.v1.<Service>/<Method>` and can never collide with `/health` or `/about`, so axum matches its own routes first and everything else falls through to gRPC. One port means one thing to configure, one thing to port-forward, and one thing to point the app at.

Tower applies the outermost `.layer` last, so `identity::resolve` sits _inside_ `GrpcWebLayer`: it sees a plain gRPC request, and the `Status` it returns for a header it cannot parse is re-framed as gRPC-Web on the way out. Outside the layer it would answer an `UNAUTHENTICATED` the client could not read as one. It is also on the gRPC router alone — `/health` must answer with an unreachable database, and resolving an identity upserts a `users` row, which is exactly the dependency that would break it.

`throttle::enforce` sits outside it and inside `GrpcWebLayer` for both of those reasons at once: a caller over their budget is refused before the upsert can write anything, and the refusal still reaches the client as a status rather than a bare HTTP code. It is on the gRPC router alone too — a health check that can be rationed is a deploy that can be made to look failed.

## The two identity headers

Every request carries `ond-user-id`, and a request naming an identity bound to an Apple account must also carry `ond-session-credential` or be refused. Neither is a field on any request message, and that is a decision about this transport rather than about the contract:

- A stream settles its headers once, when it opens. connect-swift dispatches unary calls and streams through separate interceptor protocols, so a credential carried per message is not even well defined for `ExplainTechnique` and `Chat` — `IdentityInterceptor` implements both hooks for exactly this reason, and dropping either breaks every streaming RPC at once while the unary ones keep working.
- The check belongs at the choke point `identity::resolve` already is. A field would put it in six services' handlers, where a new RPC defaults to passing.

The cost is a credential no `.proto` describes, and it is paid down in the leading comment of `account_service.proto`, which documents both headers beside the RPC that mints one.

The client keeps that random credential in Keychain and the server keeps only its one-way hash. It is a persistent device session: no timer rotates it or logs the person out, and signing in on another device does not replace it. Successful sign-out revokes that device's row; account deletion revokes every device row for the account.

## Server streaming

A streaming RPC runs over the same layer stack as a unary one — no second transport, no second client factory — so adding one is a `stream` keyword in the contract and nothing here. Today they are `AssistantService`'s `ExplainTechnique` and `Chat`.

gRPC-Web sends a server stream as several length-prefixed message frames in one response body, then the trailer frame. That is the property that makes it testable without a listener: `harness::call_grpc_web_stream_with` reads the whole body and returns the messages in the order the server wrote them, which is exactly what a client accumulating text depends on.

The two ends are asymmetric in shape, and deliberately so:

- **Rust** — the handler returns `Pin<Box<dyn Stream<Item = Result<T, Status>> + Send>>`. Both the model's chunks and the rule-based fallback are sent down it, the fallback split into paragraphs, so the client's accumulate-and-render path is the only path. A fallback that arrived as one message would leave the streaming path exercised only when a provider happened to be reachable.
- **Swift** — connect-swift hands back a `ServerOnlyAsyncStreamInterface` you `send` the request on once and then read `results()` from. `AssistantRepository` wraps that into an `AsyncThrowingStream`, so nothing above the repository boundary learns the shape — and, more usefully, a terminal `.complete` carrying a non-OK code becomes a thrown error rather than a stream that simply stops, which is otherwise indistinguishable from a short answer.

## Enum boundaries

Every proto3 enum has an `_UNSPECIFIED = 0` member that the wire format can always produce — including from a server running a newer contract than the client. Both ends convert explicitly rather than passing the generated type inwards:

- **Rust**: `crates/api/src/features/technique/service.rs` maps the database enum to the proto enum through a `match` with no catch-all, so adding a database variant without a proto variant fails to compile.
- **Swift**: `TechniqueGoal.init?(proto:)` in `OndKit` returns `nil` for `.unspecified` and `.UNRECOGNIZED`, and the repository turns that into `TechniqueRepositoryError.malformedResponse`. A value the app cannot represent is a decode failure, never a silent default.

The rule in both languages: **generated types stop at the repository boundary.** Above it, code works in domain types that have no unrepresentable state.

The one documented exception is `CopyRegister`, and it names what an exception has to argue: an unreadable register costs a tone of voice where an unreadable surface, goal or passage costs a wrong exercise — so `Routes+Decoding.swift` degrades that nil to `.plain` at the call site rather than refusing the route. The decoder still returns nil, because the arm that may be degraded is a caller's judgement about cost and never a decoder's about representability. Anything that changes what somebody breathes, hears as instructions, or has recorded about their practice is refused.

That refusal has a consequence worth stating as policy: **adding an enum value to the contract strands installed clients.** An older build receiving the new value refuses the whole message it arrived in — a new catalogue passage or goal fails the entire `ListTechniques` decode, masked only by `CachedReferenceRepository` serving its last good snapshot. Pre-launch this costs nothing, and `buf breaking` will not flag it because an addition is not a wire break. Post-launch, an enum addition needs a migration story before the value ships: release the client that decodes it first and add the value to the server's data only after that build has adoption, or version the surface. The per-value refusal stays — a silent default that draws the wrong exercise is worse than a refused decode — so the rollout order is the whole of the discipline.

## Changing the contract

```bash
# 1. Edit proto/ond/v1/…
mise run generate     # 2. Regenerate Swift + refresh the SQLx cache
mise run check        # 3. buf lint, buf breaking, clippy, tests
```

`buf breaking` compares against `main`, so a rename that would break a shipped client fails the gate. It is skipped only while the repository has no commits at all; if `main` cannot be resolved over a non-empty history, `check:proto` fails rather than skipping — see the guard in `.mise.toml`.

`check:generated` closes the other half: it regenerates the Swift and fails if the committed output differs, so a `.proto` edit cannot be committed without its generated client.
