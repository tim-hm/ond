//! `JourneyService` gRPC implementation.

use std::sync::Arc;

use tonic::{Request, Response, Status};

use crate::features::entitlement;
use crate::features::entitlement::types::Tier;
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

/// The `JourneyService` transport, holding the shared state its RPCs read the
/// pool out of.
///
/// One gRPC service over four sub-feature services — `sessions`, `bolt`,
/// `resting_rate` and `leaderboard`. The split is the domain's rather than the contract's: they
/// change for different reasons, and a client draws one screen from all of them.
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

    /// The one RPC on this service that costs a subscription.
    ///
    /// Everything else here is the caller's own practice going up and coming
    /// back, which runs on the device and is free. A board is the opposite: it
    /// is a fold across every user this server holds, computed here because it
    /// cannot be computed anywhere else, and it is on the paid side of the same
    /// line the assistant's allowance sits on.
    ///
    /// The tier is read from the caller's row rather than taken from the
    /// request, exactly as `assistant` reads it, because a client is free to
    /// claim whatever it likes. `PERMISSION_DENIED` rather than an empty board:
    /// the app draws a locked state from the refusal, and a board that came back
    /// empty would be indistinguishable from nobody having practised.
    async fn get_leaderboard(
        &self,
        request: Request<GetLeaderboardRequest>,
    ) -> Result<Response<GetLeaderboardResponse>, Status> {
        let user_id = identity::require(&request)?;

        if entitlement::service::tier(&self.state.pool, user_id).await? < Tier::Plus {
            return Err(Status::permission_denied(
                "the leaderboards are part of önd+",
            ));
        }

        let response =
            leaderboard::service::get_leaderboard(&self.state.pool, user_id, request.into_inner())
                .await?;
        Ok(Response::new(response))
    }
}
