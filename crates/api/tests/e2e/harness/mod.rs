//! A disposable database, production router, test doubles, fixtures, and a gRPC-Web client.

mod app;
mod database;
mod doubles;
mod exposition;
mod fixtures;
mod grpc_web;

use self::app::build_app_with_throttle;
pub use self::app::{build_app, build_app_with};
pub use self::database::TestDatabase;
pub use self::doubles::{
    HalfAnswer, SCRIPTED_NONCE_SEPARATOR, ScriptedIdentityVerifier, ScriptedModel, ScriptedReply,
};
pub use self::exposition::{counter_total, scrape};
pub use self::fixtures::*;
pub use self::grpc_web::{
    GrpcWebResponse, GrpcWebStream, call_grpc_web, call_grpc_web_stream_with, call_grpc_web_with,
};
