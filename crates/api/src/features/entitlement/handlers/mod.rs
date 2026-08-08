//! `EntitlementService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>` and the only one
//! barred from holding a business rule (docs/code-structure.md). A directory
//! rather than a file because the subdivision here is by protocol — `grpc` is
//! the only one, since `crate::http` owns the JSON surface.

pub mod grpc;
