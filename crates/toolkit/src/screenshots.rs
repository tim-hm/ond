//! Capture the App Store screenshot set into ios/build/screenshots.
//!
//! One device, all App Store Connect requires: the 6.9-inch iPhone, named
//! rather than resolved by size because simctl exposes no display-inches
//! field. Override with `OND_SCREENSHOT_DEVICE`. See docs/product/listing.md.

#![allow(
    clippy::print_stdout,
    reason = "the capture narrates its progress to the operator"
)]

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail, ensure};

use crate::devices::{self, Platform};

const DEFAULT_DEVICE: &str = "iPhone 17 Pro Max";

pub fn capture(repo: &Path) -> Result<()> {
    let ios = repo.join("ios");
    let name = std::env::var("OND_SCREENSHOT_DEVICE").unwrap_or_else(|_| DEFAULT_DEVICE.to_owned());
    let Some(device) = devices::named_simulator(Platform::Ios, &name)? else {
        bail!(
            "ios:screenshots: no simulator named '{name}'.\nAvailable iPhones:\n  {}\nInstall one in Xcode, or set OND_SCREENSHOT_DEVICE to one of the above.",
            devices::available_names(Platform::Ios)?.join("\n  ")
        );
    };

    // Boot is idempotent in effect but not in exit code: an already-booted
    // device exits non-zero.
    drop(simctl(&["boot", &device]));
    simctl(&["bootstatus", &device, "-b"])?;

    // A clean install per capture: a simulator carried between runs
    // accumulates every previous set on top of the last, and six weeks of
    // that reads as twelve sessions a day — which is not a person.
    drop(simctl(&["uninstall", &device, "xyz.holmie.ond"]));

    // Frozen for the reason Apple's own screenshots all read 9:41: a real
    // status bar carries the host's clock, so a set taken over two sittings
    // is visibly two sittings.
    simctl(&[
        "status_bar",
        &device,
        "override",
        "--time",
        "9:41",
        "--batteryState",
        "charged",
        "--batteryLevel",
        "100",
        "--cellularMode",
        "active",
        "--cellularBars",
        "4",
        "--wifiMode",
        "active",
        "--wifiBars",
        "3",
    ])?;

    let out = ios.join("build/screenshots");
    let result = ios.join("build/screenshots.xcresult");
    drop(std::fs::remove_dir_all(&out));
    drop(std::fs::remove_dir_all(&result));

    // Both screenshot classes, named rather than the whole bundle:
    // OndAppUITests also holds the accessibility audits, which take minutes.
    let test = Command::new("xcodebuild")
        .current_dir(&ios)
        .args([
            "-project",
            "Ond.xcodeproj",
            "-scheme",
            "Ond",
            "-destination",
            &format!("platform=iOS Simulator,id={device}"),
            "-only-testing:OndAppUITests/ScreenshotTests",
            "-only-testing:OndAppUITests/SubscriptionScreenshotTests",
            "-only-testing:OndAppUITests/OnboardingSafetyScreenshotTests",
            "-resultBundlePath",
        ])
        .arg(&result)
        .arg("test")
        .status()
        .context("run the screenshot tests")?;
    ensure!(
        test.success(),
        "ios:screenshots: the screenshot tests failed"
    );

    let export = Command::new("xcrun")
        .args(["xcresulttool", "export", "attachments", "--path"])
        .arg(&result)
        .arg("--output-path")
        .arg(&out)
        .status()
        .context("export the attachments")?;
    ensure!(
        export.success(),
        "ios:screenshots: the attachment export failed"
    );

    let renamed = rename_from_manifest(&out)?;
    println!(
        "ios:screenshots: {renamed} screenshots in {}",
        out.display()
    );

    // Cleared rather than left frozen: a simulator stuck on 9:41 is a
    // confusing thing to hand back to somebody debugging.
    simctl(&["status_bar", &device, "clear"])
}

/// Map exported attachment files back to the names the tests chose, which
/// are the listing's running order.
fn rename_from_manifest(out: &Path) -> Result<usize> {
    let manifest = out.join("manifest.json");
    if !manifest.exists() {
        println!("ios:screenshots: no manifest.json; files keep their exported names");
        return Ok(0);
    }
    let text = std::fs::read_to_string(&manifest).context("read manifest.json")?;
    let tests: Vec<ManifestTest> = serde_json::from_str(&text).context("parse manifest.json")?;

    let mut renamed = 0;
    for test in tests {
        for attachment in test.attachments {
            let Some(name) = chosen_name(&attachment.suggested_human_readable_name) else {
                continue;
            };
            let source = out.join(&attachment.exported_file_name);
            if !source.exists() {
                continue;
            }
            std::fs::rename(&source, out.join(format!("{name}.png")))
                .with_context(|| format!("rename {}", attachment.exported_file_name))?;
            renamed += 1;
        }
    }
    Ok(renamed)
}

#[derive(serde::Deserialize)]
struct ManifestTest {
    #[serde(default)]
    attachments: Vec<ManifestAttachment>,
}

#[derive(serde::Deserialize)]
struct ManifestAttachment {
    #[serde(rename = "exportedFileName", default)]
    exported_file_name: String,
    #[serde(rename = "suggestedHumanReadableName", default)]
    suggested_human_readable_name: String,
}

/// The name the test chose, out of `<name>_<index>_<uuid>.png` — the only
/// field that carries it, and it carries it mangled. Parsed from the end
/// rather than split on a literal `_0_`, which silently misnamed any
/// attachment that was not the first of its name.
fn chosen_name(suggested: &str) -> Option<&str> {
    let stem = suggested.strip_suffix(".png")?;
    if stem.len() < 37 {
        return None;
    }
    let (rest, uuid) = stem.split_at(stem.len() - 36);
    if !uuid.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
        return None;
    }
    let rest = rest.strip_suffix('_')?;
    let name = rest.trim_end_matches(|c: char| c.is_ascii_digit());
    if name.len() == rest.len() {
        return None;
    }
    let name = name.strip_suffix('_')?;
    (!name.is_empty()).then_some(name)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_chosen_name_survives_the_mangling() {
        assert_eq!(
            chosen_name("01-home_0_ABCDEF01-2345-6789-ABCD-EF0123456789.png"),
            Some("01-home")
        );
        assert_eq!(
            chosen_name("with_underscores_12_ABCDEF01-2345-6789-ABCD-EF0123456789.png"),
            Some("with_underscores")
        );
    }

    /// The second attachment of a name carries index 1, not 0 — the case the
    /// original `_0_` split misnamed.
    #[test]
    fn a_later_attachment_of_the_same_name_still_parses() {
        assert_eq!(
            chosen_name("06-coach_1_ABCDEF01-2345-6789-ABCD-EF0123456789.png"),
            Some("06-coach")
        );
    }

    #[test]
    fn non_matching_names_are_left_alone() {
        assert_eq!(chosen_name("not-a-screenshot.txt"), None);
        assert_eq!(chosen_name("bare.png"), None);
        assert_eq!(
            chosen_name("no-index_ABCDEF01-2345-6789-ABCD-EF0123456789.png"),
            None
        );
        assert_eq!(
            chosen_name("_0_ABCDEF01-2345-6789-ABCD-EF0123456789.png"),
            None
        );
    }
}
