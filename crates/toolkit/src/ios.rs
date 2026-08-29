//! Install-and-launch flows for the simulators and the hardware.
//!
//! The builds themselves stay behind the mise task graph (`ios:sim:*` depend
//! on `ios:build:*`); this module owns what comes after: selection, the
//! `StoreKit` sync, the install, and the launch.

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail, ensure};

use crate::devices::{self, Platform, built_products_dir};

const APP_ID: &str = "xyz.holmie.ond";
const WATCH_APP_ID: &str = "xyz.holmie.ond.watchkitapp";

pub fn sim_phone(repo: &Path) -> Result<()> {
    let ios = repo.join("ios");
    let device = devices::booted_simulator(
        Platform::Ios,
        "ios:sim:phone",
        "Open one with `open -a Simulator`, or boot a named device with\n`xcrun simctl list devices available` then `xcrun simctl boot <name>`.",
    )?;
    let products = built_products_dir(&ios, "Ond", "generic/platform=iOS Simulator")?;
    sync_storekit(&ios, &device)?;
    simctl(&["install", &device, &format!("{products}/Ond.app")])?;
    simctl(&["launch", &device, APP_ID])
}

pub fn sim_watch(repo: &Path) -> Result<()> {
    let ios = repo.join("ios");
    let device = devices::booted_simulator(
        Platform::WatchOs,
        "ios:sim:watch",
        "Boot one by name from `xcrun simctl list devices available`, or pair\nit to a phone simulator first — `xcrun simctl list pairs` shows both.",
    )?;
    let products = built_products_dir(&ios, "OndWatch", "generic/platform=watchOS Simulator")?;
    // No StoreKit sync, unlike the phone: purchasing lives on the phone, and
    // the watch app resolves no products of its own.
    simctl(&["install", &device, &format!("{products}/OndWatch.app")])?;
    simctl(&["launch", &device, WATCH_APP_ID])
}

pub fn device_phone(repo: &Path) -> Result<()> {
    signing_team("ios:device:phone")?;
    let ios = repo.join("ios");
    let device = devices::hardware(
        Platform::Ios,
        "ios:device:phone",
        "Plug an iPhone in or bring it onto this network, unlock it, and trust\nthis Mac if it asks. `xcrun devicectl list devices` shows what it can see.",
    )?;
    build_for_hardware(&ios, "Ond", "generic/platform=iOS")?;
    let products = built_products_dir(&ios, "Ond", "generic/platform=iOS")?;
    devicectl(&[
        "device",
        "install",
        "app",
        "--device",
        &device,
        &format!("{products}/Ond.app"),
    ])?;
    devicectl(&["device", "process", "launch", "--device", &device, APP_ID])
}

pub fn device_watch(repo: &Path) -> Result<()> {
    signing_team("ios:device:watch")?;
    let ios = repo.join("ios");
    let device = devices::hardware(
        Platform::WatchOs,
        "ios:device:watch",
        "The Mac reaches the wrist through its paired iPhone: wake and unlock\nboth, and enable Developer Mode on the watch itself.\n`xcrun devicectl list devices` shows what it can currently see.",
    )?;
    build_for_hardware(&ios, "OndWatch", "generic/platform=watchOS")?;
    let products = built_products_dir(&ios, "OndWatch", "generic/platform=watchOS")?;

    // Retried once: the bridge drops this connection often enough to have
    // done it on this task's first run — CoreDeviceError 3002, an interrupted
    // XPC connection that succeeds immediately on a second attempt.
    let app = format!("{products}/OndWatch.app");
    let install = [
        "device",
        "install",
        "app",
        "--device",
        device.as_str(),
        app.as_str(),
    ];
    if devicectl(&install).is_err() {
        #[allow(clippy::print_stderr, reason = "the retry must be visible in the run")]
        {
            eprintln!("ios:device:watch: the install connection dropped, retrying once.");
        }
        devicectl(&install)?;
    }
    devicectl(&[
        "device",
        "process",
        "launch",
        "--device",
        &device,
        WATCH_APP_ID,
    ])
}

/// Run the iPhone accessibility UI suite on the booted simulator.
///
/// Screenshot classes are deliberately skipped: they assert almost nothing,
/// take a minute, and are driven by `ios:screenshots` against one specific
/// device size.
pub fn ui_test(repo: &Path) -> Result<()> {
    let ios = repo.join("ios");
    let device = devices::booted_simulator(
        Platform::Ios,
        "test:ui:phone",
        "Open one with `open -a Simulator` and try again.",
    )?;
    let status = Command::new("xcodebuild")
        .current_dir(&ios)
        .args([
            "-project",
            "Ond.xcodeproj",
            "-scheme",
            "Ond",
            "-destination",
            &format!("platform=iOS Simulator,id={device}"),
            "-only-testing:OndAppUITests",
            "-skip-testing:OndAppUITests/ScreenshotTests",
            "-skip-testing:OndAppUITests/SubscriptionScreenshotTests",
            "-skip-testing:OndAppUITests/OnboardingSafetyScreenshotTests",
            "test",
        ])
        .status()
        .context("run xcodebuild test")?;
    ensure!(status.success(), "test:ui:phone: the UI suite failed");
    Ok(())
}

/// Copy the `StoreKit` configuration into storekitd's own container.
/// `storeKitConfiguration` in project.yml is a scheme property, and only
/// Xcode runs schemes: without this copy the app resolves no products and
/// every purchase fails as `productUnavailable`. A missing container fails
/// loudly, because the whole point is that its absence was silent.
fn sync_storekit(ios: &Path, device: &str) -> Result<()> {
    let data = simctl_output(&["getenv", device, "SIMULATOR_SHARED_RESOURCES_DIRECTORY"])?;
    let groups = Path::new(data.trim()).join("Containers/Shared/AppGroup");
    let mut container = None;
    for entry in std::fs::read_dir(&groups).with_context(|| format!("read {}", groups.display()))? {
        let candidate = entry?.path();
        let metadata = candidate.join(".com.apple.mobile_container_manager.metadata.plist");
        // The group is looked up by identifier rather than a path holding a
        // per-simulator UUID; most containers carry no such key.
        let identifier = Command::new("plutil")
            .args(["-extract", "MCMMetadataIdentifier", "raw", "-o", "-"])
            .arg(&metadata)
            .output()
            .context("run plutil")?;
        if identifier.status.success()
            && String::from_utf8_lossy(&identifier.stdout).trim() == "group.com.apple.storekit"
        {
            container = Some(candidate);
            break;
        }
    }
    let container =
        container.context("no group.com.apple.storekit container on the booted simulator")?;

    let configuration = container.join(format!("Documents/Persistence/Octane/{APP_ID}"));
    std::fs::create_dir_all(&configuration).context("create the StoreKit configuration dir")?;
    std::fs::copy(
        ios.join("Ond/Ond.storekit"),
        configuration.join("Configuration.storekit"),
    )
    .context("copy Ond.storekit into the container")?;

    // storekitd holds the configuration it read at launch, so a first sync or
    // a changed price reaches the app only after it re-reads this file. Its
    // failure is tolerated the way Xcode tolerates it.
    drop(
        Command::new("xcrun")
            .args([
                "simctl",
                "spawn",
                device,
                "launchctl",
                "kickstart",
                "-k",
                "system/com.apple.storekitd",
            ])
            .output(),
    );
    Ok(())
}

fn build_for_hardware(ios: &Path, scheme: &str, destination: &str) -> Result<()> {
    // `-allowProvisioningUpdates` because a widget extension is a second
    // bundle identifier needing its own profile; without it the first device
    // build after one is added cannot sign.
    let status = Command::new("xcodebuild")
        .current_dir(ios)
        .args([
            "-project",
            "Ond.xcodeproj",
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-allowProvisioningUpdates",
            "build",
        ])
        .status()
        .context("run xcodebuild build")?;
    ensure!(status.success(), "the {scheme} device build failed");
    Ok(())
}

fn signing_team(task: &str) -> Result<()> {
    if std::env::var("OND_DEV_TEAM").is_ok_and(|team| !team.is_empty()) {
        return Ok(());
    }
    bail!(
        "{task}: OND_DEV_TEAM is unset, so nothing signs.\nIt belongs in .env. See docs/contributing.md."
    )
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

fn simctl_output(args: &[&str]) -> Result<String> {
    let output = Command::new("xcrun")
        .arg("simctl")
        .args(args)
        .output()
        .context("run simctl")?;
    ensure!(output.status.success(), "simctl {} failed", args.join(" "));
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn devicectl(args: &[&str]) -> Result<()> {
    let status = Command::new("xcrun")
        .arg("devicectl")
        .args(args)
        .status()
        .context("run devicectl")?;
    ensure!(status.success(), "devicectl {} failed", args.join(" "));
    Ok(())
}
