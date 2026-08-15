//! `EntitlementService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>` and the only one
//! barred from holding a business rule (docs/code-structure.md). The gRPC
//! client boundary and private Prometheus boundary stay separate because only
//! the latter owns product-wide census presentation.

pub mod grpc;
pub mod metrics;
