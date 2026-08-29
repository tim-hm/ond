//! `EntitlementService`'s transport. Handlers are the only layer that
//! receives `Arc<AppState>` and the only one barred from holding a business
//! rule (docs/code-structure.md). The census query is this feature's, but
//! `obs::exposition` composes every gauge owner's refresh, so no feature
//! imports another to be scraped.

pub mod grpc;
