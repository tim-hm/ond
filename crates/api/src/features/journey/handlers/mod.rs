//! `JourneyService`'s transport.
//!
//! Handlers are the only layer that receives `Arc<AppState>`, and the only one
//! barred from holding a business rule (docs/code-structure.md). `grpc` is the
//! only protocol here; `crate::http` owns the JSON surface.

pub mod grpc;
