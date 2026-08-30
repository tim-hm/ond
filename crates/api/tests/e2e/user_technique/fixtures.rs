//! What every user-technique test builds its world out of.
//!
//! Here rather than in each file because all four suites compose drafts out of
//! the same phases, and a second copy of a builder is a second place for a
//! duration to drift out of the seeded range.

pub(super) use api::identity::USER_ID_HEADER;
pub(super) use api::proto::ond::v1 as pb;
pub(super) use physiology::TIMED_HOLD_CEILING_MS;
pub(super) use tonic::Code;

pub(super) use crate::harness::{
    self, GrpcWebResponse, TestDatabase, call_grpc_web, call_grpc_web_with,
};

pub(super) const LIST: &str = "/ond.v1.UserTechniqueService/ListUserTechniques";
pub(super) const UPDATE: &str = "/ond.v1.UserTechniqueService/UpdateUserTechnique";
pub(super) const DELETE: &str = "/ond.v1.UserTechniqueService/DeleteUserTechnique";

/// Two stable, valid identities. Fixed rather than random so a failing test
/// leaves rows someone can go and look at.
pub(super) const USER: &str = "3f2b1c4d-0000-4000-8000-000000000101";
pub(super) const OTHER_USER: &str = "3f2b1c4d-0000-4000-8000-000000000102";

/// Something plainly inside every seeded range: four seconds in, eight out, ten
/// times over. The exercise somebody who has found what works for them would
/// actually write down.
pub(super) fn draft() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Long exhale, mine".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Sleep as i32,
        stages: vec![stage(
            10,
            vec![
                inhale(pb::Passage::Nose, 4000),
                exhale(pb::Passage::Nose, 8000),
            ],
        )],
        rounds: 1,
    }
}

/// Alternate-nostril breathing, composed rather than curated: in through the
/// left, out through the right, in through the right, out through the left.
/// It was unbuildable before the passage was on the wire — the composer could
/// only reach a 4:6:4:6 rhythm, which the catalogue already holds twice over.
pub(super) fn alternate_nostril() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Nadi shodhana, mine".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Focus as i32,
        stages: vec![stage(
            9,
            vec![
                inhale(pb::Passage::LeftNostril, 4000),
                exhale(pb::Passage::RightNostril, 6000),
                inhale(pb::Passage::RightNostril, 4000),
                exhale(pb::Passage::LeftNostril, 6000),
            ],
        )],
        rounds: 1,
    }
}

pub(super) fn inhale(passage: pb::Passage, duration_ms: u32) -> pb::DraftPhase {
    phase(
        pb::draft_phase::Movement::Inhale(passage as i32),
        duration_ms,
    )
}

pub(super) fn exhale(passage: pb::Passage, duration_ms: u32) -> pb::DraftPhase {
    phase(
        pb::draft_phase::Movement::Exhale(passage as i32),
        duration_ms,
    )
}

/// One hold, with no lungs state on it — which of the two it becomes is the
/// server's to derive from the breath before it.
pub(super) fn hold(duration_ms: u32) -> pb::DraftPhase {
    phase(pb::draft_phase::Movement::Hold(pb::Hold {}), duration_ms)
}

pub(super) fn phase(movement: pb::draft_phase::Movement, duration_ms: u32) -> pb::DraftPhase {
    pb::DraftPhase {
        duration_ms,
        movement: Some(movement),
    }
}

/// Three differently-shaped stages, three times over — the user-built equivalent
/// of a staged protocol. Every stage has a distinct cycle count and phase count
/// so that a stage arriving in the wrong slot reads as a wrong number rather
/// than as a coincidence.
pub(super) fn sequence() -> pb::TechniqueDraft {
    pb::TechniqueDraft {
        name: "Wake, hold, settle".to_owned(),
        summary: String::new(),
        goal: pb::TechniqueGoal::Energy as i32,
        stages: vec![
            stage(
                6,
                vec![
                    inhale(pb::Passage::Nose, 2000),
                    exhale(pb::Passage::Nose, 2000),
                ],
            ),
            stage(
                1,
                vec![
                    inhale(pb::Passage::Nose, 4000),
                    hold(8000),
                    exhale(pb::Passage::Nose, 8000),
                ],
            ),
            stage(
                4,
                vec![
                    inhale(pb::Passage::Nose, 3000),
                    exhale(pb::Passage::Nose, 6000),
                ],
            ),
        ],
        rounds: 3,
    }
}

pub(super) fn stage(cycles: u32, phases: Vec<pb::DraftPhase>) -> pb::DraftStage {
    pb::DraftStage { phases, cycles }
}

/// Each stage as its cycle count and how many phases it holds — enough to tell
/// three stages apart without restating every duration.
pub(super) fn shape(technique: &pb::Technique) -> Vec<(u32, usize)> {
    technique
        .stages
        .iter()
        .map(|stage| (stage.cycles, stage.phases.len()))
        .collect()
}

pub(super) const fn request() -> pb::ListUserTechniquesRequest {
    pb::ListUserTechniquesRequest {}
}

pub(super) async fn list(
    db: &TestDatabase,
    user: &str,
) -> GrpcWebResponse<pb::ListUserTechniquesResponse> {
    call_grpc_web_with(db.app(), LIST, &request(), &[(USER_ID_HEADER, user)]).await
}

pub(super) async fn create(
    db: &TestDatabase,
    user: &str,
    draft: Option<pb::TechniqueDraft>,
) -> GrpcWebResponse<pb::CreateUserTechniqueResponse> {
    call_grpc_web_with(
        db.app(),
        harness::CREATE_USER_TECHNIQUE,
        &pb::CreateUserTechniqueRequest { draft },
        &[(USER_ID_HEADER, user)],
    )
    .await
}

pub(super) async fn update(
    db: &TestDatabase,
    user: &str,
    id: &str,
    draft: pb::TechniqueDraft,
) -> GrpcWebResponse<pb::UpdateUserTechniqueResponse> {
    call_grpc_web_with(
        db.app(),
        UPDATE,
        &pb::UpdateUserTechniqueRequest {
            id: id.to_owned(),
            draft: Some(draft),
        },
        &[(USER_ID_HEADER, user)],
    )
    .await
}
