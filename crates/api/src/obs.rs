//! Telemetry: request tracing and Prometheus recorder mechanics. Logging
//! convention (docs/observability.md): log at boundaries, stay silent in
//! between. The transport-wide request record belongs here rather than to any
//! feature handler; product-specific metrics stay with the feature that
//! defines what they mean.

mod completion;
pub mod exposition;
pub mod metrics;
mod trace;

pub use trace::{
    DEFAULT_FILTER, RequestComplete, RequestSpan, init, mark_probes, record_user_id, trace_layer,
};
