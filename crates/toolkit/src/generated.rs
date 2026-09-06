use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, ensure};

pub fn check(repo: &Path, diagrams: bool) -> Result<()> {
    let (paths, tasks): (&[&str], &[&str]) = if diagrams {
        (&["web/index.html"], &["generate:diagrams"])
    } else {
        (
            &[
                "ios/Packages/OndCore/Sources/OndAPI/Generated",
                "ios/Packages/OndCore/Sources/OndKit/Resources/catalogue.json",
                "web/favicon.ico",
                "web/apple-touch-icon.png",
                "ios/OndWatch/Assets.xcassets/AppIcon.appiconset",
            ],
            &["generate:proto", "generate:catalogue", "generate:icons"],
        )
    };
    let before = snapshot(repo, paths)?;
    for task in tasks {
        let status = Command::new("mise")
            .current_dir(repo)
            .args(["run", task])
            .status()
            .with_context(|| format!("run {task}"))?;
        ensure!(status.success(), "{task} failed");
    }
    let after = snapshot(repo, paths)?;
    ensure!(
        before == after,
        "Generated artifacts changed. Review the generated diff and rerun the check."
    );
    Ok(())
}

fn snapshot(repo: &Path, paths: &[&str]) -> Result<BTreeMap<PathBuf, Vec<u8>>> {
    let mut files = BTreeMap::new();
    for relative in paths {
        collect(&repo.join(relative), &mut files)?;
    }
    Ok(files)
}

fn collect(path: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) -> Result<()> {
    if path.is_dir() {
        for entry in std::fs::read_dir(path)? {
            collect(&entry?.path(), files)?;
        }
    } else if path.exists() {
        files.insert(path.to_owned(), std::fs::read(path)?);
    }
    Ok(())
}
