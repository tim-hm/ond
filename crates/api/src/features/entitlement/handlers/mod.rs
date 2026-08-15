//! `EntitlementService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>` and the only one
//! barred from holding a business rule (docs/code-structure.md).
//!
//! The Prometheus boundary is not here. The census query and its labels are
//! this feature's, in `super::metrics`, but composing every gauge owner's
//! refresh is not entitlement's job — `obs::exposition` does that, so no
//! feature has to import another to be scraped.

pub mod grpc;
