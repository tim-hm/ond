//! Simulator and hardware selection shared by the ios: and test: tasks.
//!
//! One parser for the seven call sites that used to paste it. Simulators are
//! selected inside their runtime's section heading rather than by device
//! name, because model names change every autumn and the heading does not —
//! and an unscoped match can pick a watch whose name contains the phone's.

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result};

#[derive(Clone, Copy)]
pub enum Platform {
    Ios,
    WatchOs,
}

impl Platform {
    /// The `simctl list devices` section heading prefix.
    fn heading(self) -> &'static str {
        match self {
            Self::Ios => "-- iOS",
            Self::WatchOs => "-- watchOS",
        }
    }

    /// The devicectl model-column marker: the product type names the surface,
    /// so a paired watch never wins the phone's selection.
    fn model(self) -> &'static str {
        match self {
            Self::Ios => "(iPhone",
            Self::WatchOs => "(Watch",
        }
    }
}

/// The booted simulator for `platform`, by udid.
///
/// Picked out of the platform's section rather than passed to simctl as
/// `booted`, which resolves only while exactly one simulator is up — testing
/// the phone against the wrist means booting both halves of a pair.
pub fn booted_simulator(platform: Platform, task: &str, hint: &str) -> Result<String> {
    let listing = simctl_list("booted")?;
    simulator_udids(&listing, platform)
        .into_iter()
        .next()
        .with_context(|| {
            format!(
                "{task}: no booted simulator for {}.\n{hint}",
                platform.heading().trim_start_matches("-- ")
            )
        })
}

/// Any available simulator for `platform`, booted or not.
pub fn available_simulator(platform: Platform) -> Result<Option<String>> {
    let listing = simctl_list("available")?;
    Ok(simulator_udids(&listing, platform).into_iter().next())
}

/// The available simulator whose device name is exactly `name`.
pub fn named_simulator(platform: Platform, name: &str) -> Result<Option<String>> {
    let listing = simctl_list("available")?;
    let matcher = format!("{name} (");
    Ok(section(&listing, platform)
        .into_iter()
        .filter(|line| line.contains(&matcher))
        .find_map(udid_in))
}

/// Every available device name for the platform, for a not-found hint.
pub fn available_names(platform: Platform) -> Result<Vec<String>> {
    let listing = simctl_list("available")?;
    Ok(section(&listing, platform)
        .into_iter()
        .filter_map(|line| Some(line.trim().split(" (").next()?.to_owned()))
        .collect())
}

/// A reachable piece of hardware for `platform`, by `CoreDevice` identifier.
///
/// Only the unreachable states are excluded: devicectl calls a wirelessly
/// paired device "available (paired)" rather than "connected" and installs
/// to it perfectly well.
pub fn hardware(platform: Platform, task: &str, hint: &str) -> Result<String> {
    let output = Command::new("xcrun")
        .args(["devicectl", "list", "devices"])
        .output()
        .context("run devicectl list devices")?;
    let listing = String::from_utf8_lossy(&output.stdout).into_owned();
    hardware_udid(&listing, platform)
        .with_context(|| format!("{task}: no reachable hardware for this Mac.\n{hint}"))
}

fn simctl_list(filter: &str) -> Result<String> {
    let output = Command::new("xcrun")
        .args(["simctl", "list", "devices", filter])
        .output()
        .context("run simctl list devices")?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn section(listing: &str, platform: Platform) -> Vec<&str> {
    let mut inside = false;
    let mut lines = Vec::new();
    for line in listing.lines() {
        if line.starts_with(platform.heading()) {
            inside = true;
            continue;
        }
        if line.starts_with("--") {
            inside = false;
            continue;
        }
        if inside {
            lines.push(line);
        }
    }
    lines
}

fn simulator_udids(listing: &str, platform: Platform) -> Vec<String> {
    section(listing, platform)
        .into_iter()
        .filter_map(udid_in)
        .collect()
}

fn hardware_udid(listing: &str, platform: Platform) -> Option<String> {
    listing
        .lines()
        .filter(|line| {
            let lowered = line.to_lowercase();
            !lowered.contains("unavailable") && !lowered.contains("disconnected")
        })
        .filter(|line| has_model(line, platform.model()))
        .find_map(udid_in)
}

/// Whether the line carries a product type like `(iPhone18,1)`.
fn has_model(line: &str, marker: &str) -> bool {
    line.match_indices(marker).any(|(index, _)| {
        line[index + marker.len()..]
            .split_once(')')
            .is_some_and(|(inner, _)| {
                let Some((digits, minor)) = inner.split_once(',') else {
                    return false;
                };
                !digits.is_empty()
                    && digits.chars().all(|c| c.is_ascii_digit())
                    && !minor.is_empty()
                    && minor.chars().all(|c| c.is_ascii_digit())
            })
    })
}

fn udid_in(line: &str) -> Option<String> {
    line.split(|c: char| c == '(' || c == ')' || c.is_whitespace())
        .find(|token| is_udid(token))
        .map(str::to_owned)
}

fn is_udid(token: &str) -> bool {
    token.len() == 36
        && token.char_indices().all(|(index, c)| {
            if matches!(index, 8 | 13 | 18 | 23) {
                c == '-'
            } else {
                c.is_ascii_hexdigit()
            }
        })
}

/// `BUILT_PRODUCTS_DIR` for a scheme, asked of xcodebuild rather than
/// assumed, because `DerivedData`'s path is a hash of the project's location.
pub fn built_products_dir(ios: &Path, scheme: &str, destination: &str) -> Result<String> {
    let output = Command::new("xcodebuild")
        .current_dir(ios)
        .args([
            "-project",
            "Ond.xcodeproj",
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-showBuildSettings",
        ])
        .output()
        .context("run xcodebuild -showBuildSettings")?;
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .find_map(|line| {
            let (key, value) = line.split_once(" = ")?;
            key.trim()
                .eq("BUILT_PRODUCTS_DIR")
                .then(|| value.to_owned())
        })
        .context("BUILT_PRODUCTS_DIR is not in the build settings")
}

#[cfg(test)]
mod tests {
    use super::*;

    const BOOTED_PAIR: &str = "\
== Devices ==
-- iOS 26.5 --
    iPhone 17 Pro Max (20F3D8A4-510A-46CC-B388-C4C170E1F5D9) (Booted)
-- watchOS 26.5 --
    Apple Watch Series 11 (46mm) (AEBE1213-5645-4C41-9A97-62AC58CB3517) (Booted)
";

    const HARDWARE: &str = "\
Name                Hostname                           Identifier                             State                Model
-----------------   --------------------------------   ------------------------------------   ------------------   -------------------------------
Tim's Apple Watch   Tims-AppleWatch.coredevice.local   9FD3B2D9-3802-509E-9EC1-566A0957F7F5   available (paired)   Apple Watch Series 9 (Watch7,2)
pluto               pluto.coredevice.local             F8D5AB24-7BFF-5DEF-8D35-13C8F53661DD   unavailable          iPhone 17 Pro (iPhone18,1)
";

    #[test]
    fn a_booted_watch_does_not_win_the_phone_selection() {
        assert_eq!(
            simulator_udids(BOOTED_PAIR, Platform::Ios),
            vec!["20F3D8A4-510A-46CC-B388-C4C170E1F5D9"]
        );
        assert_eq!(
            simulator_udids(BOOTED_PAIR, Platform::WatchOs),
            vec!["AEBE1213-5645-4C41-9A97-62AC58CB3517"]
        );
    }

    #[test]
    fn an_empty_section_selects_nothing() {
        let listing = "== Devices ==\n-- iOS 26.5 --\n-- watchOS 26.5 --\n";
        assert!(simulator_udids(listing, Platform::Ios).is_empty());
    }

    /// A wirelessly paired watch reads "available (paired)", not "connected",
    /// and must still be selected; an unavailable phone must not be.
    #[test]
    fn hardware_selection_excludes_only_unreachable_states() {
        assert_eq!(
            hardware_udid(HARDWARE, Platform::WatchOs),
            Some("9FD3B2D9-3802-509E-9EC1-566A0957F7F5".to_owned())
        );
        assert_eq!(hardware_udid(HARDWARE, Platform::Ios), None);
    }

    /// The watch's row names an iPhone in its hostname column on some
    /// pairings; the product type in the model column is what selects.
    #[test]
    fn the_model_column_picks_the_surface() {
        assert!(has_model("Apple Watch Series 9 (Watch7,2)", "(Watch"));
        assert!(!has_model("Apple Watch Series 9 (Watch7,2)", "(iPhone"));
        assert!(!has_model("no model here", "(iPhone"));
        assert!(!has_model("(iPhone18)", "(iPhone"));
    }

    #[test]
    fn named_selection_requires_the_exact_name() {
        let listing = "\
== Devices ==
-- iOS 26.5 --
    iPhone 17 Pro (6B4431C1-0784-4052-9303-05342E69D5A8) (Shutdown)
    iPhone 17 Pro Max (20F3D8A4-510A-46CC-B388-C4C170E1F5D9) (Shutdown)
";
        let matcher = "iPhone 17 Pro Max (";
        let found: Vec<String> = section(listing, Platform::Ios)
            .into_iter()
            .filter(|line| line.contains(matcher))
            .filter_map(udid_in)
            .collect();
        assert_eq!(found, vec!["20F3D8A4-510A-46CC-B388-C4C170E1F5D9"]);
    }
}
