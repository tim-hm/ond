//! `EntitlementService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>` and the only one
//! barred from holding a business rule (docs/code-structure.md).
//!
//! The Prometheus boundary used to be a second handler here, rendering the whole
//! exposition from inside this feature. It moved to `obs::exposition` once a
//! second and third feature grew gauges — the census query and its labels stay
//! this feature's, in `super::metrics`, but composing every owner's refresh is
//! not entitlement's job.

pub mod grpc;
