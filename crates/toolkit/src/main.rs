//! Repo tooling that is too much for a mise task and has no business being a
//! loose script.
//!
//! Subcommands take no flags: every path they need is a fact about this
//! repository rather than a choice — the manifests, the resource folder they
//! render into, and the credential that reaches neither.

use std::path::PathBuf;

use anyhow::{Result, bail};

mod voice;

#[tokio::main]
async fn main() -> Result<()> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = root.join("../..").canonicalize()?;
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["voice"] => {
            voice::render(
                &root.join("voice"),
                &repo.join("ios/Packages/OndCore/Sources/OndKit/Resources/Voice"),
            )
            .await
        }
        ["voice", "list"] => voice::list().await,
        other => bail!("usage: toolkit voice [list] (got {other:?})"),
    }
}
