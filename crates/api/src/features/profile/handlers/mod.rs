//! `ProfileService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>` and the only one
//! barred from holding a business rule (docs/code-structure.md). A directory
//! because the subdivision is by protocol; `crate::http` owns the JSON surface.

pub mod grpc;
