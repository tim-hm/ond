//! The deploy: build the release image, ship it to the box, migrate, restart.
//!
//! One box and no registry, so `docker save | ssh docker load` is the whole
//! supply chain. The remote steps live in `infra/box/box-up.sh`, a real file
//! `sh -n` can check. See docs/deployment.md.

#![allow(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "the deploy narrates its progress to the operator"
)]

use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail, ensure};

use crate::{box_config, git};

/// The infra outputs the render and the shipping need, checked by name so a
/// missing or empty output stops the deploy before anything moves.
const PLACEHOLDER_OUTPUTS: &[(&str, &str)] = &[
    ("__REGION__", "region"),
    ("__ALARM_TOPIC_ARN__", "alarm_topic_arn"),
    ("__BACKUP_BUCKET__", "backup_bucket"),
    ("__HEARTBEAT_NAMESPACE__", "heartbeat_namespace"),
    ("__HEARTBEAT_METRIC__", "heartbeat_metric"),
    ("__LOGS_BUCKET__", "logs_bucket"),
    ("__API_HOST__", "api_host"),
    ("__WEB_HOST__", "web_host"),
];

pub fn api(repo: &Path) -> Result<()> {
    advisory_gate(repo)?;
    let commit = shippable_commit(repo)?;

    // Passed in rather than read by build.rs: .dockerignore excludes .git, so
    // the build context holds no repository to ask.
    run(
        Command::new("docker").current_dir(repo).args([
            "build",
            "--platform",
            "linux/arm64",
            "--build-arg",
            &format!("GIT_COMMIT_HASH={commit}"),
            "-t",
            "ond-api:latest",
            ".",
        ]),
        "build the release image",
    )?;

    let mut values = std::collections::BTreeMap::new();
    for (placeholder, output) in PLACEHOLDER_OUTPUTS {
        values.insert(*placeholder, infra_output(repo, output)?);
    }
    box_config::render(repo, &|name| values.get(name).cloned())?;

    let host = format!("ubuntu@{}", infra_output(repo, "ssh_host")?);
    ship_image(repo, &host)?;
    // `--exclude` keeps the templates on this machine: a `.tmpl` beside the
    // rendered file invites editing the wrong one.
    run(
        Command::new("rsync").current_dir(repo).args([
            "-az",
            "--exclude",
            "*.tmpl",
            "infra/box/",
            &format!("{host}:/srv/ond/"),
        ]),
        "rsync infra/box to the box",
    )?;
    run(
        Command::new("ssh").args([&host, "sudo sh /srv/ond/box-up.sh"]),
        "run box-up.sh on the box",
    )
}

pub fn website(repo: &Path) -> Result<()> {
    fetch_main(repo, "deploy:website");
    let drift = drifted_paths(repo, Some("web/"))?;
    if !drift.is_empty() {
        match acknowledged("DEPLOY_DRIFT_ACK") {
            Some(reason) => eprintln!("deploy:website: drift acknowledged — {reason}"),
            None => bail!(
                "deploy:website: web/ is not origin/main, refusing to publish what has not landed:\n{}\nland it, or set DEPLOY_DRIFT_ACK=\"<why>\" to publish anyway",
                drift.join("\n")
            ),
        }
    }
    let host = format!("ubuntu@{}", infra_output(repo, "ssh_host")?);
    run(
        Command::new("rsync").current_dir(repo).args([
            "-az",
            "--delete",
            "web/",
            &format!("{host}:/srv/ond/web/"),
        ]),
        "rsync web/ to the box",
    )
}

/// Fail when AWS is not what infra/ describes; `-detailed-exitcode` asks the
/// provider rather than the repository, because a resource deleted in the
/// console drifts without a commit touching anything.
pub fn drift(repo: &Path) -> Result<()> {
    let status = Command::new("tofu")
        .current_dir(repo.join("infra"))
        .args([
            "plan",
            "-detailed-exitcode",
            "-input=false",
            "-compact-warnings",
        ])
        .status()
        .context("run tofu plan")?;
    match status.code() {
        Some(0) => Ok(()),
        Some(2) => {
            eprintln!("infra:drift: AWS is not what infra/ describes — the plan above is pending.");
            match acknowledged("INFRA_DRIFT_ACK") {
                Some(reason) => {
                    eprintln!("infra:drift: acknowledged — {reason}");
                    Ok(())
                }
                None => bail!(
                    "infra:drift: run `mise run infra:apply`, or set INFRA_DRIFT_ACK=\"<why>\" to proceed anyway"
                ),
            }
        }
        _ => bail!("infra:drift: the plan itself failed — the question was not answered"),
    }
}

/// An escape hatch's reason, when its variable carries one. Opt-in per
/// invocation so the default stays fail-closed, and a sentence rather than a
/// boolean so the reason travels with the run.
pub fn acknowledged(variable: &str) -> Option<String> {
    std::env::var(variable)
        .ok()
        .filter(|reason| !reason.is_empty())
}

/// The advisory watch, run at deploy time because the gate is offline by
/// design and Actions are disabled — see docs/deployment.md.
fn advisory_gate(repo: &Path) -> Result<()> {
    let status = Command::new("mise")
        .current_dir(repo)
        .args(["run", "check:audit"])
        .status()
        .context("run mise run check:audit")?;
    if status.success() {
        return Ok(());
    }
    eprintln!("deploy:api: the advisory scan flagged Cargo.lock or Package.resolved (above).");
    match acknowledged("DEPLOY_ADVISORY_ACK") {
        Some(reason) => {
            eprintln!("deploy:api: advisory acknowledged — {reason}");
            Ok(())
        }
        None => bail!(
            "deploy:api: update the dependency, or set DEPLOY_ADVISORY_ACK=\"<why>\" to ship anyway"
        ),
    }
}

/// The hash /about will report. From `origin/main` rather than HEAD, because
/// deploys run from the gitbutler/workspace branch, whose HEAD is a synthetic
/// commit no branch contains — /about must name something a reader can open.
fn shippable_commit(repo: &Path) -> Result<String> {
    fetch_main(repo, "deploy:api");
    let commit = git::output(
        repo,
        &["rev-parse", "--short", "origin/main"],
        "resolve origin/main",
    )?
    .trim()
    .to_owned();

    let drift = drifted_paths(repo, None)?;
    if drift.is_empty() {
        return Ok(commit);
    }
    match acknowledged("DEPLOY_DRIFT_ACK") {
        // The shipped hash says -dirty, so the shortcut stays visible in
        // /about days later.
        Some(reason) => {
            eprintln!("deploy:api: drift acknowledged — {reason}");
            eprintln!("{}", drift.join("\n"));
            Ok(format!("{commit}-dirty"))
        }
        None => bail!(
            "deploy:api: the working tree is not origin/main ({commit}), refusing to ship a hash that describes something else:\n{}\nland the work and `but pull`, or set DEPLOY_DRIFT_ACK=\"<why>\" to ship it reported as -dirty",
            drift.join("\n")
        ),
    }
}

/// A failed fetch is a warning, not a stop: the last fetched origin/main is
/// still a pushed commit, and a GitHub outage should not also mean the box
/// cannot be redeployed.
fn fetch_main(repo: &Path, task: &str) {
    let fetched = Command::new("git")
        .current_dir(repo)
        .args([
            "fetch",
            "--quiet",
            "origin",
            "+refs/heads/main:refs/remotes/origin/main",
        ])
        .status();
    if !fetched.is_ok_and(|status| status.success()) {
        eprintln!("{task}: could not fetch origin/main, comparing against the last fetched state");
    }
}

/// Files that differ from origin/main, committed or not, plus untracked
/// files — which reach the build context and the rsyncs without ever
/// reaching a commit.
fn drifted_paths(repo: &Path, scope: Option<&str>) -> Result<Vec<String>> {
    let mut diff_args = vec!["diff", "--name-only", "origin/main", "--"];
    let mut untracked_args = vec!["ls-files", "--others", "--exclude-standard"];
    if let Some(scope) = scope {
        diff_args.push(scope);
        untracked_args.extend(["--", scope]);
    }
    let mut paths: Vec<String> = git::output(repo, &diff_args, "diff against origin/main")?
        .lines()
        .chain(git::output(repo, &untracked_args, "list untracked files")?.lines())
        .map(str::to_owned)
        .collect();
    paths.sort();
    Ok(paths)
}

/// One `tofu output -raw` value. `-raw` per value rather than one `-json`
/// parse, so a missing output stops the deploy by name; an empty answer —
/// which `-raw` is entitled to give — is refused for `box_config`'s reason.
fn infra_output(repo: &Path, name: &str) -> Result<String> {
    let output = Command::new("tofu")
        .current_dir(repo)
        .args(["-chdir=infra", "output", "-raw", name])
        .output()
        .with_context(|| format!("read infra output {name}"))?;
    ensure!(
        output.status.success(),
        "infra output {name} could not be read: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    let value = String::from_utf8(output.stdout)
        .with_context(|| format!("infra output {name} is not UTF-8"))?
        .trim()
        .to_owned();
    ensure!(!value.is_empty(), "infra output {name} is empty");
    Ok(value)
}

fn ship_image(repo: &Path, host: &str) -> Result<()> {
    let mut save = Command::new("docker")
        .current_dir(repo)
        .args(["save", "ond-api:latest"])
        .stdout(Stdio::piped())
        .spawn()
        .context("start docker save")?;
    let save_stdout = save.stdout.take().context("capture docker save stdout")?;
    let mut gzip = Command::new("gzip")
        .stdin(save_stdout)
        .stdout(Stdio::piped())
        .spawn()
        .context("start gzip")?;
    let gzip_stdout = gzip.stdout.take().context("capture gzip stdout")?;
    let load = Command::new("ssh")
        .args([host, "gunzip | docker load"])
        .stdin(gzip_stdout)
        .status()
        .context("load the image on the box")?;
    ensure!(save.wait()?.success(), "docker save failed");
    ensure!(gzip.wait()?.success(), "gzip failed");
    ensure!(load.success(), "docker load on the box failed");
    Ok(())
}

fn run(command: &mut Command, operation: &str) -> Result<()> {
    let status = command.status().with_context(|| operation.to_owned())?;
    ensure!(status.success(), "could not {operation}");
    Ok(())
}
