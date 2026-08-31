//! Caller isolation and per-person technique ceilings.

use api::identity::USER_ID_HEADER;
use api::proto::ond::v1 as pb;
use tonic::Code;

use super::fixtures::{OTHER_USER, USER, create, draft, list, request, update};
use crate::harness::{
    DELETE_USER_TECHNIQUE, LIST_USER_TECHNIQUES, TestDatabase, call_grpc_web, call_grpc_web_with,
};

/// One person's exercises are not another's, on every RPC that names an id.
///
/// The whole credential is a UUID somebody generated, so the ownership predicate
/// is the only thing between two callers — and it has to be on the write paths,
/// not just the read.
#[tokio::test]
async fn one_persons_exercises_are_invisible_to_another() {
    let db = TestDatabase::create("user_technique_isolation").await;

    let mine = create(&db, USER, Some(draft()))
        .await
        .into_ok()
        .technique
        .expect("the create succeeds");

    assert!(
        list(&db, OTHER_USER).await.into_ok().techniques.is_empty(),
        "somebody else's list is empty"
    );

    let stolen = update(&db, OTHER_USER, &mine.id, draft()).await;

    assert_eq!(stolen.status, Code::NotFound as i32);

    let deleted = call_grpc_web_with::<_, pb::DeleteUserTechniqueResponse>(
        db.app(),
        DELETE_USER_TECHNIQUE,
        &pb::DeleteUserTechniqueRequest { id: mine.id },
        &[(USER_ID_HEADER, OTHER_USER)],
    )
    .await;

    assert_eq!(
        deleted.status,
        Code::Ok as i32,
        "a delete stays idempotent for a stranger"
    );
    assert_eq!(
        list(&db, USER).await.into_ok().techniques.len(),
        1,
        "and it deleted nothing"
    );
}

/// There is no anonymous half of this service, unlike the catalogue's.
#[tokio::test]
async fn an_unidentified_caller_has_no_exercises_to_read() {
    let db = TestDatabase::create("user_technique_anonymous").await;

    let response = call_grpc_web::<_, pb::ListUserTechniquesResponse>(
        db.app(),
        LIST_USER_TECHNIQUES,
        &request(),
    )
    .await;

    assert_eq!(response.status, Code::Unauthenticated as i32);
}

/// A person's own exercises are theirs, but the number of them is this
/// database's — and the caller's whole credential is a UUID they minted.
#[tokio::test]
async fn the_number_a_person_may_keep_is_bounded() {
    let db = TestDatabase::create("user_technique_ceiling").await;

    let ceiling = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served")
        .max_techniques;

    for index in 0..ceiling {
        let mut another = draft();
        another.name = format!("Mine {index}");
        assert_eq!(
            create(&db, USER, Some(another)).await.status,
            Code::Ok as i32,
            "the {index}th exercise is still inside the ceiling"
        );
    }

    // `FailedPrecondition`, not the throttle's `ResourceExhausted`: the cap
    // must stay distinguishable from "try again in a minute".
    assert_eq!(
        create(&db, USER, Some(draft())).await.status,
        Code::FailedPrecondition as i32
    );
}

/// The ceiling holds under concurrency: with one slot left, five simultaneous
/// creates admit exactly one. The count rides inside the insert's transaction
/// behind a per-person lock, so racing creates cannot both read nineteen and
/// both land.
#[tokio::test]
async fn racing_creates_cannot_pierce_the_ceiling() {
    let db = TestDatabase::create("user_technique_race").await;

    let ceiling = list(&db, USER)
        .await
        .into_ok()
        .limits
        .expect("the limits are served")
        .max_techniques;

    for index in 0..ceiling - 1 {
        let mut another = draft();
        another.name = format!("Mine {index}");
        assert_eq!(
            create(&db, USER, Some(another)).await.status,
            Code::Ok as i32
        );
    }

    let contender = |index: u32| {
        let mut another = draft();
        another.name = format!("Racing {index}");
        create(&db, USER, Some(another))
    };
    let outcomes = tokio::join!(
        contender(0),
        contender(1),
        contender(2),
        contender(3),
        contender(4)
    );
    let statuses = [
        outcomes.0.status,
        outcomes.1.status,
        outcomes.2.status,
        outcomes.3.status,
        outcomes.4.status,
    ];

    let admitted = statuses
        .iter()
        .filter(|status| **status == Code::Ok as i32)
        .count();
    assert_eq!(admitted, 1, "one slot admits one create: {statuses:?}");
    for status in statuses {
        assert!(
            status == Code::Ok as i32 || status == Code::FailedPrecondition as i32,
            "a racing create is admitted or refused, never broken: {status}"
        );
    }

    let listed = list(&db, USER).await.into_ok().techniques.len();
    assert_eq!(listed, ceiling as usize);
}
