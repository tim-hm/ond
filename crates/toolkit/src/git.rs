//! Git facts shared by the landed-state checks and the deploy.

use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail, ensure};

/// The landed baseline: `origin/main` first, because a `GitButler` workspace
/// does not keep local `main` current and a stale baseline passes checks it
/// should fail. Neither resolving is an error, not a skip — the detached and
/// shallow checkouts where resolution fails are where this matters most.
pub fn landed_ref(repo: &Path) -> Result<&'static str> {
    for reference in ["origin/main", "main"] {
        let status = Command::new("git")
            .args(["rev-parse", "--verify", "--quiet", reference])
            .current_dir(repo)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .with_context(|| format!("check whether git ref {reference} exists"))?;
        if status.success() {
            return Ok(reference);
        }
    }
    bail!("cannot resolve `origin/main` or `main`, refusing to skip a landed-state check")
}

/// Run git in `repo` and return its stdout, failing on a non-zero exit.
pub fn output(repo: &Path, args: &[&str], operation: &str) -> Result<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .with_context(|| format!("run git to {operation}"))?;
    ensure!(
        output.status.success(),
        "git could not {operation}: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    String::from_utf8(output.stdout)
        .with_context(|| format!("git output for {operation} is not UTF-8"))
}
