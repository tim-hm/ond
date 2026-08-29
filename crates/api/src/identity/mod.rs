//! Who is calling, resolved once for every gRPC request. Anonymous callers
//! send a client-minted UUID — possession of the id *is* the claim. A verified
//! sign-in mints a credential (256 random bits, returned once, stored only as
//! a SHA-256); [`resolve`] fails closed for a bound row and asks an unbound
//! one for nothing. Sign-in can merge a row away between requests (see `account::repository::merge`).

mod credential;
mod middleware;
mod repository;

pub use credential::{CredentialHash, SessionCredential, SessionError};
pub use middleware::{
    SESSION_CREDENTIAL_HEADER, SupportReference, USER_ID_HEADER, UserId, presented_credential,
    require, resolve,
};
pub use repository::{end_session, start_session};
