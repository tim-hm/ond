//! `JourneyService` gRPC implementation.

use std::sync::Arc;

use tonic::{Request, Response, Status};

use crate::features::journey::{bolt, leaderboard, resting_rate, sessions};
use crate::identity;
use crate::proto::ond::v1::journey_service_server::JourneyService;
use crate::proto::ond::v1::{
    DeleteSessionsRequest, DeleteSessionsResponse, GetJourneyRequest, GetJourneyResponse,
    GetLeaderboardRequest, GetLeaderboardResponse, RecordBoltScoreRequest, RecordBoltScoreResponse,
    RecordRestingRateRequest, RecordRestingRateResponse, RecordSessionsRequest,
    RecordSessionsResponse,
};
use crate::state::AppState;

/// The `JourneyService` transport, holding the state its RPCs read the pool from.
///
/// One gRPC service over four sub-feature services. The split is the domain's,
/// not the contract's: a client draws one screen from all of them.
pub struct JourneyServiceImpl {
    state: Arc<AppState>,
}

impl JourneyServiceImpl {
    pub const fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

/// Every RPC here is scoped to one person, and a caller with no identity has no
/// journey to be shown — including on the leaderboards, where the response
/// carries the caller's own standing.
#[tonic::async_trait]
impl JourneyService for JourneyServiceImpl {
    async fn record_sessions(
        &self,
        request: Request<RecordSessionsRequest>,
    ) -> Result<Response<RecordSessionsResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response = sessions::service::record_sessions(
            &self.state.pool,
            user_id,
            request.into_inner().sessions,
        )
        .await?;
        Ok(Response::new(response))
    }

    async fn delete_sessions(
        &self,
        request: Request<DeleteSessionsRequest>,
    ) -> Result<Response<DeleteSessionsResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response = sessions::service::delete_sessions(
            &self.state.pool,
            user_id,
            request.into_inner().client_session_ids,
        )
        .await?;
        Ok(Response::new(response))
    }

    async fn get_journey(
        &self,
        request: Request<GetJourneyRequest>,
    ) -> Result<Response<GetJourneyResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response =
            sessions::service::get_journey(&self.state.pool, user_id, request.into_inner()).await?;
        Ok(Response::new(response))
    }

    async fn record_bolt_score(
        &self,
        request: Request<RecordBoltScoreRequest>,
    ) -> Result<Response<RecordBoltScoreResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response =
            bolt::service::record_bolt_score(&self.state.pool, user_id, request.into_inner())
                .await?;
        Ok(Response::new(response))
    }

    async fn record_resting_rate(
        &self,
        request: Request<RecordRestingRateRequest>,
    ) -> Result<Response<RecordRestingRateResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response = resting_rate::service::record_resting_rate(
            &self.state.pool,
            user_id,
            request.into_inner(),
        )
        .await?;
        Ok(Response::new(response))
    }

    /// The one RPC on this service that costs a subscription, which the service
    /// says rather than this transport — see `leaderboard::service`.
    async fn get_leaderboard(
        &self,
        request: Request<GetLeaderboardRequest>,
    ) -> Result<Response<GetLeaderboardResponse>, Status> {
        let user_id = identity::require(&request)?;
        let response =
            leaderboard::service::get_leaderboard(&self.state.pool, user_id, request.into_inner())
                .await?;
        Ok(Response::new(response))
    }
}
