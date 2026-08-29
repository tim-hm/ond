//! `cargo machete` with its exit code made honest.
//!
//! When machete's `cargo metadata` call fails — an unparseable manifest, a
//! cold registry index with no network — it reports the crate it could not
//! read, skips it, prints "didn't find any unused dependencies" and exits 0:
//! a green gate that analysed nothing. Matching its prose is the cost of
//! catching that; if upstream rewords the line this silently passes again.

use std::io::Write;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, ensure};

pub fn check(repo: &Path) -> Result<()> {
    // The binary directly rather than `cargo machete`: under a nested cargo
    // (this toolkit runs via `cargo run`) machete reads the subcommand word
    // as a path and dies on it.
    let output = Command::new("cargo-machete")
        .current_dir(repo)
        .arg("--with-metadata")
        .output()
        .context("run cargo-machete")?;
    std::io::stderr()
        .write_all(&output.stderr)
        .context("relay cargo machete stderr")?;
    ensure!(output.status.success(), "cargo machete failed");
    ensure!(
        !String::from_utf8_lossy(&output.stderr).contains("error when handling "),
        "check:deps: cargo machete could not read every crate (see the errors above), so \"no unused dependencies\" only covers the ones it did"
    );
    Ok(())
}
