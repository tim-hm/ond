# Codebase health audit

Audited 13 August 2026. This is the living record for the Rust backend, shared Swift package, iPhone and watch applications, database contract, tests, and developer tooling. Dated reports under `docs/audits/` remain historical snapshots; progress on the current remediation is recorded here.

## Overall health

The codebase has strong foundations. Its feature-first Rust layout, narrow protobuf boundary, Swift package products, typed domain models, migration discipline, and mise-owned workflows form clear layers. Comments usually explain constraints and invariants rather than narrating syntax. Rust and Swift both avoid routine type-safety escape hatches, and the test suite is broad and predominantly integration-focused.

The remediated validation completed with 204 Rust unit tests, 146 Rust e2e tests, 776 Swift tests, one live Swift/backend smoke, and two iPhone UI tests passing. Two paid Bedrock smoke tests are intentionally ignored. The accepted operational gaps below are resolved; CI remains the one deliberate deferral.

## Findings

| ID | Severity | Finding and evidence | Decision | Status | Verification |
| --- | --- | --- | --- | --- | --- |
| AUTH-001 | High | `identity::standing` refreshed `last_seen_at`, while `start_session` only swept idle rows during a later sign-in. The privacy page promised a 90-day lifetime that the request path did not enforce. | Make device credentials persistent until sign-out or account deletion. | Resolved | `mise run test:e2e` |
| STRUCT-001 | Medium | `bedrock.rs`, `prompt.rs`, and the e2e harness contained several independently testable responsibilities in files of roughly 1,000 lines. | Split along their existing client/event/wire, prefix/instruction, and harness service seams without changing callers. | Resolved | `mise run test:rs && mise run test:e2e` |
| TEST-001 | Medium | Swift transport tests stopped at doubles and did not prove that the committed Swift client speaks to the live tonic gRPC-Web server. | Add an explicit live catalogue smoke test. | Resolved | `mise run test:swift:live` |
| TEST-002 | Medium | No UI automation checked the accessibility of Home or an active breathing session. | Add a small iPhone XCUITest accessibility suite. | Resolved | `mise run test:ui:phone` |
| TEST-003 | Low | One full nextest run reported a transient inherited-output-handle `LEAK`; an isolated rerun was clean. This was not evidence of a Rust memory leak. | Give teardown 500 ms, then fail any process that still leaks. | Resolved | `mise run test:e2e` |
| TEST-004 | Low | Neither language reported coverage, so changes in exercised first-party code were invisible. | Add informational Rust and Swift terminal summaries with no percentage gate. | Resolved | `mise run coverage` |
| DELIVERY-001 | Medium | The local validation suite is not run by CI. | Deliberately defer CI until the product is generating revenue. | Deferred | Revisit when the product is generating revenue. |

## Known exclusions

- The ignored Bedrock smoke tests make paid calls and remain opt-in.
- A real Apple identity-provider acceptance path is not part of routine tests.
- The first UI suite covers iPhone Home and an active session, not watchOS.
- Coverage is informational and does not impose a minimum percentage.

## Final validation

`mise run generate`, `mise run fmt`, and `mise run check` passed in repository order. The gate observed 204 Rust unit tests and 146 e2e tests passing; nextest reported no `LEAK` or `LEAK-FAIL` result. `mise run check:swift`, `mise run test:swift`, `mise run check:diagrams`, `mise run test:swift:live`, and `mise run test:ui:phone` passed, with 776 Swift package tests, 11 live catalogue exercises, and two UI tests observed.

Informational coverage completed at 88.58% Rust line coverage and 74.27% first-party Swift line coverage. `mise run test:system` correctly refused to take over port 18100 while an existing local API was listening; its live-smoke and UI constituents passed independently against that API. No CI configuration was added or changed.
