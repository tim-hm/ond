//! Repo tooling that is too much for a mise task and has no business being a
//! loose script.
//!
//! One subcommand so far. It takes no flags because every path it needs is a
//! fact about this repository rather than a choice: the manifests, the resource
//! folder they render into, and a cache under `target/` that is not committed.

use std::path::PathBuf;

use anyhow::{Result, bail};

mod voice;

#[tokio::main]
async fn main() -> Result<()> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = root.join("../..").canonicalize()?;

    match std::env::args().nth(1).as_deref() {
        Some("voice") => {
            voice::render(
                &root.join("voice"),
                &repo.join("ios/Packages/OndCore/Sources/OndKit/Resources/Voice"),
                &repo.join("target/voice-cache"),
            )
            .await
        }
        Some(other) => bail!("no such subcommand: {other}"),
        None => bail!("usage: toolkit voice"),
    }
}
