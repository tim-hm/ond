//! `TechniqueService` gRPC implementation.

use std::sync::Arc;

use tonic::{Request, Response, Status};

use crate::features::technique::service;
use crate::proto::ond::v1::technique_service_server::TechniqueService;
use crate::proto::ond::v1::{
    ListFoundationsRequest, ListFoundationsResponse, ListRoutesRequest, ListRoutesResponse,
    ListTechniquesRequest, ListTechniquesResponse,
};
use crate::state::AppState;

/// The `TechniqueService` transport, holding the shared state its RPCs read the
/// pool out of.
pub struct TechniqueServiceImpl {
    state: Arc<AppState>,
}

impl TechniqueServiceImpl {
    pub const fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

/// The one service that never calls `identity::require`. The catalogue is public
/// reference data, so requiring an identity to read it would gate the app's first
/// screen on a Keychain write — which is why `identity::resolve` lets a request
/// carrying no header through at all.
#[tonic::async_trait]
impl TechniqueService for TechniqueServiceImpl {
    async fn list_techniques(
        &self,
        _request: Request<ListTechniquesRequest>,
    ) -> Result<Response<ListTechniquesResponse>, Status> {
        let response = service::list_techniques(&self.state.pool).await?;
        Ok(Response::new(response))
    }

    async fn list_foundations(
        &self,
        _request: Request<ListFoundationsRequest>,
    ) -> Result<Response<ListFoundationsResponse>, Status> {
        let response = service::list_foundations(&self.state.pool).await?;
        Ok(Response::new(response))
    }

    async fn list_routes(
        &self,
        _request: Request<ListRoutesRequest>,
    ) -> Result<Response<ListRoutesResponse>, Status> {
        let response = service::list_routes(&self.state.pool).await?;
        Ok(Response::new(response))
    }
}
