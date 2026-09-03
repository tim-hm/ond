//! `test:system`: a live backend plus the on-simulator suites, with the API
//! lifecycle owned here so a failed suite still stops the server and any
//! simulator this run booted.

#![allow(
    clippy::print_stderr,
    reason = "the run narrates its progress to the operator"
)]

use std::net::TcpStream;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};

use crate::devices::{self, Platform};

const API: &str = "127.0.0.1:29100";

pub async fn run(repo: &Path) -> Result<()> {
    ensure!(
        TcpStream::connect_timeout(&API.parse()?, Duration::from_millis(300)).is_err(),
        "test:system: port 29100 is already occupied; stop the existing server first."
    );

    let mut cleanup = Cleanup::default();

    if devices::booted_simulator(Platform::Ios, "test:system", "").is_err() {
        let device = devices::available_simulator(Platform::Ios)?
            .context("test:system: no available iOS simulator.")?;
        simctl(&["boot", &device])?;
        simctl(&["bootstatus", &device, "-b"])?;
        cleanup.started_simulator = Some(device);
    }

    let log_path = repo.join("target/test-system-api.log");
    std::fs::create_dir_all(repo.join("target")).context("create target/")?;
    let log = std::fs::File::create(&log_path).context("create the API log file")?;
    let api = Command::new("cargo")
        .current_dir(repo)
        .args(["run", "-p", "api"])
        .stdout(Stdio::from(
            log.try_clone().context("clone the log handle")?,
        ))
        .stderr(Stdio::from(log))
        .spawn()
        .context("start the API")?;
    cleanup.api = Some(api);

    let mut healthy = false;
    for _ in 0..60 {
        tokio::time::sleep(Duration::from_secs(1)).await;
        if reqwest::get("http://localhost:29100/health")
            .await
            .is_ok_and(|response| response.status().is_success())
        {
            healthy = true;
            break;
        }
    }
    if !healthy {
        bail!(
            "test:system: API did not become healthy; see {}.",
            log_path.display()
        );
    }

    mise(repo, "test:swift:live")?;
    mise(repo, "test:ui:phone")
}

#[derive(Default)]
struct Cleanup {
    api: Option<Child>,
    started_simulator: Option<String>,
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        if let Some(api) = &mut self.api {
            drop(api.kill());
            drop(api.wait());
        }
        if let Some(device) = &self.started_simulator {
            drop(
                Command::new("xcrun")
                    .args(["simctl", "shutdown", device])
                    .output(),
            );
        }
    }
}

fn mise(repo: &Path, task: &str) -> Result<()> {
    let status = Command::new("mise")
        .current_dir(repo)
        .args(["run", task])
        .status()
        .with_context(|| format!("run mise run {task}"))?;
    ensure!(status.success(), "test:system: {task} failed");
    Ok(())
}

fn simctl(args: &[&str]) -> Result<()> {
    let status = Command::new("xcrun")
        .arg("simctl")
        .args(args)
        .status()
        .context("run simctl")?;
    ensure!(status.success(), "simctl {} failed", args.join(" "));
    Ok(())
}
