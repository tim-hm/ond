//! Whole-technique replacement and idempotent deletion.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use tonic::Code;

use super::fixtures::{USER, create, draft, list, update};
use crate::harness::{DELETE_USER_TECHNIQUE, TestDatabase, call_grpc_web_with};

/// Editing replaces the whole exercise, including a shape change — a phase
/// removed from the middle renumbers everything after it, which is the case a
/// rewrite gets right for free and a patch does not.
#[tokio::test]
async fn editing_replaces_the_whole_exercise() {
    let db = TestDatabase::create("user_technique_edit").await;

    let created = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    let mut edited = draft();
    edited.name = "Shorter".to_owned();
    edited.stages[0].phases.truncate(1);
    edited.stages[0].cycles = 4;

    let updated = update(&db, USER, &created.id, edited)
        .await
        .into_ok()
        .technique
        .expect("the update answers with the technique it stored");

    assert_eq!(updated.id, created.id, "an edit keeps its identity");
    assert_eq!(updated.name, "Shorter");
    assert_eq!(updated.stages[0].phases.len(), 1);
    assert_eq!(updated.stages[0].cycles, 4);

    let listed = list(&db, USER).await.into_ok();
    assert_eq!(listed.techniques.len(), 1, "an edit is not a second copy");
    assert_eq!(listed.techniques[0], updated);
}

/// Deleting removes it, and deleting it again succeeds.
///
/// The second half is the point: a client that retried a delete whose answer it
/// never saw must converge rather than be told about a technique the person can
/// no longer see.
#[tokio::test]
async fn deleting_is_idempotent() {
    let db = TestDatabase::create("user_technique_delete").await;

    let created = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    for _ in 0..2 {
        let deleted = call_grpc_web_with::<_, pb::DeleteUserTechniqueResponse>(
            db.app(),
            DELETE_USER_TECHNIQUE,
            &pb::DeleteUserTechniqueRequest {
                id: created.id.clone(),
            },
            &[(USER_ID_HEADER, USER)],
        )
        .await;

        assert_eq!(deleted.status, Code::Ok as i32);
    }

    assert!(list(&db, USER).await.into_ok().techniques.is_empty());
}
