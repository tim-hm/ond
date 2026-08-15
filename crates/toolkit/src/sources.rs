//! Walking the repository for source files, for the checks that read code
//! rather than one known file.
//!
//! Three checks had grown their own recursion over `read_dir`. They agreed on
//! the interesting part and differed on the accidental one — whether the walk
//! recursed or used an explicit stack, whether a failure named the directory it
//! failed in — so a fix to one never reached the others, and the newest had no
//! way to skip a directory at all.

use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};

/// Every file under `directory` with the given extension, depth-first.
///
/// `skip` is asked about directories only, before descending. Filtering
/// individual files is the caller's job: the checks that need it are excluding
/// one known path, which is a comparison at the call site rather than a rule
/// this function should know.
pub fn source_files(
    directory: &Path,
    extension: &str,
    skip: &dyn Fn(&Path) -> bool,
) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    collect(directory, extension, skip, &mut files)?;
    Ok(files)
}

fn collect(
    directory: &Path,
    extension: &str,
    skip: &dyn Fn(&Path) -> bool,
    files: &mut Vec<PathBuf>,
) -> Result<()> {
    for entry in fs::read_dir(directory)
        .with_context(|| format!("read source directory at {}", directory.display()))?
    {
        let entry = entry.with_context(|| format!("read entry in {}", directory.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .with_context(|| format!("read file type for {}", path.display()))?;

        if file_type.is_dir() {
            if !skip(&path) {
                collect(&path, extension, skip, files)?;
            }
            continue;
        }

        if file_type.is_file() && path.extension().is_some_and(|found| found == extension) {
            files.push(path);
        }
    }

    Ok(())
}

/// Descends into everything.
///
/// Named rather than written as a closure at each call site, so "this walk
/// excludes nothing" is a deliberate statement rather than something to infer
/// from an empty body.
pub fn no_skip(_: &Path) -> bool {
    false
}
