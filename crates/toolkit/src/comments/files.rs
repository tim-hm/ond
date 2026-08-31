//! Two paths git tracks that the cap still never reads: generated code, which
//! nobody writes, and the landed migrations, which nobody may edit. Adding a
//! format here without adding its skip rule puts the cap on files whose author
//! cannot answer it.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use anyhow::Result;

use super::scan::language;
use crate::git;

/// Every file the prose cap reads, sorted.
///
/// Git's listing rather than a filesystem walk, so gitignored render outputs
/// and build directories never reach the scanner. Untracked files are
/// included, so a new file is capped before its first commit.
pub fn files(repo: &Path) -> Result<Vec<PathBuf>> {
    let tracked = git::output(repo, &["ls-files"], "list tracked files")?;
    let untracked = git::output(
        repo,
        &["ls-files", "--others", "--exclude-standard"],
        "list untracked files",
    )?;
    let deleted = git::output(repo, &["ls-files", "--deleted"], "list deleted files")?;
    Ok(listed_files(repo, &tracked, &untracked, &deleted))
}

fn listed_files(repo: &Path, tracked: &str, untracked: &str, deleted: &str) -> Vec<PathBuf> {
    let deleted: BTreeSet<&str> = deleted.lines().collect();
    let mut found: Vec<PathBuf> = tracked
        .lines()
        .chain(untracked.lines())
        .filter(|path| !deleted.contains(path))
        .filter(|path| language(Path::new(path)).is_some())
        .filter(|path| !skipped(path))
        .map(|path| repo.join(path))
        .collect();
    found.sort();
    found.dedup();
    found
}

/// Paths git tracks that the cap still never reads: generated code, and the
/// landed migrations that `migrations::check` forbids editing at all.
fn skipped(path: &str) -> bool {
    path.contains("/Generated/") || path.starts_with("crates/migrate/migrations/")
}

/// How a scanned file is named in output: repo-relative, forward slashes.
pub fn relative(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_selection_covers_supported_formats_and_omits_deletions() {
        let repo = Path::new("/repo");
        let tracked = "a.rs\na.tf\na.css\na.html\na.ts\na.river\na.plist\na.xcprivacy\na.svg\nDockerfile\ngone.rs\nCargo.lock\n";
        let found = listed_files(repo, tracked, "new.swift\n", "gone.rs\n");
        let names: Vec<&str> = found
            .iter()
            .map(|path| path.strip_prefix(repo).unwrap().to_str().unwrap())
            .collect();
        assert_eq!(
            names,
            [
                "Dockerfile",
                "a.css",
                "a.html",
                "a.plist",
                "a.river",
                "a.rs",
                "a.svg",
                "a.tf",
                "a.ts",
                "a.xcprivacy",
                "new.swift",
            ]
        );
    }
}
