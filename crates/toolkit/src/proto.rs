//! The protobuf breaking-change check against the landed contract.
//!
//! Measured against `git::landed_ref` — the same baseline rule as
//! `migrations::check`, because two checks answering "what has landed"
//! differently is how one ends up wrong. No fetch: `mise run check` is a pure
//! function of the tree and runs offline, and the last fetched origin/main is
//! a commit that really did land, so the baseline is behind at worst.

#![allow(
    clippy::print_stderr,
    reason = "the acknowledgement must be visible in the run's output"
)]

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, ensure};

use crate::{deploy, git};

pub fn check(repo: &Path) -> Result<()> {
    let landed = git::landed_ref(repo)?;
    let against = format!("../.git#ref={landed},subdir=proto");
    let mut breaking = Command::new("buf");
    breaking
        .current_dir(repo.join("proto"))
        .args(["breaking", "--against", &against]);

    // The escape hatch for a commit that breaks the contract on purpose,
    // defensible only while no client has shipped. The check still runs and
    // prints every finding, so nothing is hidden from review.
    if let Some(reason) = deploy::acknowledged("PROTO_BREAKING_ACK") {
        eprintln!("check:proto: breaking changes acknowledged — {reason}");
        breaking.status().context("run buf breaking")?;
        return Ok(());
    }

    let status = breaking.status().context("run buf breaking")?;
    ensure!(
        status.success(),
        "check:proto: the contract breaks against {landed} (findings above)"
    );
    Ok(())
}
