//! `cargo machete` with its exit code made honest.
//!
//! When machete cannot read a crate it says so, skips it, then prints
//! "didn't find any unused dependencies" and exits 0 — a green gate that
//! analysed nothing. Matching its prose is the only way to catch that.

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
