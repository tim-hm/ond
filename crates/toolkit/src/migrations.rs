//! Guards the append-only SQL migration history against the copy on main.
//!
//! `SQLx` stores a checksum for every migration a database applies. A changed or
//! reordered landed file therefore passes against fresh test databases and
//! first fails in production, where the old checksum already exists. Git is the
//! manifest here: it says which migrations have landed without adding a second
//! checksum file that could be regenerated beside the edit it was meant to
//! catch.

use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{Context, Result, bail, ensure};

use crate::git;

const MIGRATIONS_DIR: &str = "crates/migrate/migrations";

/// Verifies that landed migrations are unchanged and every new one is appended.
///
/// `origin/main` is preferred because a `GitButler` workspace does not keep local
/// `main` current. If neither ref resolves, the check fails rather than silently
/// skipping on the detached or shallow checkouts where the guard matters most.
pub fn check(repo: &Path) -> Result<()> {
    let landed = git::landed_ref(repo)?;
    let applied = applied_migrations(repo, landed)?;
    ensure!(
        !applied.is_empty(),
        "check:migrations: {landed} carries no migrations, which cannot be right"
    );

    reject_applied_changes(repo, landed, &applied)?;

    let present = present_migrations(repo)?;
    validate_catalogue(landed, &applied, &present)
}

fn applied_migrations(repo: &Path, landed: &str) -> Result<Vec<String>> {
    let listed = git::output(
        repo,
        &[
            "ls-tree",
            "--name-only",
            landed,
            "--",
            &format!("{MIGRATIONS_DIR}/"),
        ],
        "list landed migrations",
    )?;
    let mut migrations = listed
        .lines()
        .filter(|path| {
            Path::new(path)
                .extension()
                .is_some_and(|extension| extension == "sql")
        })
        .map(str::to_owned)
        .collect::<Vec<_>>();
    migrations.sort();
    Ok(migrations)
}

fn reject_applied_changes(repo: &Path, landed: &str, applied: &[String]) -> Result<()> {
    let output = Command::new("git")
        .args(["diff", "--name-status", landed, "--"])
        .args(applied)
        .current_dir(repo)
        .output()
        .context("compare landed migrations with the working tree")?;
    ensure!(
        output.status.success(),
        "check:migrations: git could not compare landed migrations with the working tree: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    let changes = String::from_utf8(output.stdout)
        .context("git diff output for landed migrations is not UTF-8")?;
    if changes.trim().is_empty() {
        return Ok(());
    }

    let indented = changes
        .lines()
        .map(|line| format!("  {line}"))
        .collect::<Vec<_>>()
        .join("\n");
    bail!(
        "check:migrations: a migration already applied on {landed} has changed:\n{indented}\n\
         sqlx checksums every applied migration, so editing one — a comment included — breaks\n\
         `mise run migrate` against every database that has run it, production among them.\n\
         Restore the file and put the change in a new migration."
    )
}

fn present_migrations(repo: &Path) -> Result<Vec<String>> {
    let directory = repo.join(MIGRATIONS_DIR);
    let mut migrations = fs::read_dir(&directory)
        .with_context(|| format!("read {}", directory.display()))?
        .map(|entry| {
            let path = entry?.path();
            Ok(path)
        })
        .collect::<std::io::Result<Vec<PathBuf>>>()?
        .into_iter()
        .filter(|path| path.extension().is_some_and(|extension| extension == "sql"))
        .map(|path| {
            path.strip_prefix(repo)
                .context("migration path is outside the repository")?
                .to_str()
                .map(str::to_owned)
                .context("migration path is not UTF-8")
        })
        .collect::<Result<Vec<_>>>()?;
    migrations.sort();
    Ok(migrations)
}

fn validate_catalogue(landed: &str, applied: &[String], present: &[String]) -> Result<()> {
    let misnamed = present
        .iter()
        .filter(|path| !valid_name(path))
        .map(|path| format!("  {path}"))
        .collect::<Vec<_>>();
    ensure!(
        misnamed.is_empty(),
        "check:migrations: every migration must be named `NNNN_lower_snake_case.sql`:\n{}\n\
         The four zero-padded digits are what make filename order equal the order sqlx applies them in.",
        misnamed.join("\n")
    );

    let highest = applied
        .last()
        .context("the landed migration catalogue is empty")?;
    let applied = applied.iter().collect::<BTreeSet<_>>();

    for file in present {
        if file > highest || applied.contains(file) {
            continue;
        }

        let highest_name = Path::new(highest)
            .file_name()
            .and_then(|name| name.to_str())
            .context("the highest landed migration has no UTF-8 filename")?;
        bail!(
            "check:migrations: {file} sorts at or below {highest_name}, which {landed} has already applied.\n\
             A new migration has to sort after every landed one. Slotting one in below the high-water mark\n\
             changes the order sqlx applies them in, and a database that has already run the landed set can\n\
             never reproduce that order."
        );
    }

    Ok(())
}

fn valid_name(path: &str) -> bool {
    let Some(name) = Path::new(path).file_name().and_then(|name| name.to_str()) else {
        return false;
    };
    let Some(stem) = name.strip_suffix(".sql") else {
        return false;
    };
    let bytes = stem.as_bytes();
    bytes.len() > 5
        && bytes[..4].iter().all(u8::is_ascii_digit)
        && bytes[4] == b'_'
        && bytes[5..]
            .iter()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn migration(name: &str) -> String {
        format!("{MIGRATIONS_DIR}/{name}")
    }

    #[test]
    fn migration_names_are_four_digits_and_lower_snake_case() {
        for name in ["0001_init.sql", "0042_add_v2_field.sql"] {
            assert!(valid_name(&migration(name)), "{name}");
        }
        for name in [
            "001_init.sql",
            "0001.sql",
            "0001-words.sql",
            "0001_Upper.sql",
            "0001_words.txt",
        ] {
            assert!(!valid_name(&migration(name)), "{name}");
        }
    }

    #[test]
    fn an_appended_migration_is_valid() {
        let applied = [migration("0001_init.sql"), migration("0002_more.sql")];
        let present = [
            migration("0001_init.sql"),
            migration("0002_more.sql"),
            migration("0003_next.sql"),
        ];

        assert!(validate_catalogue("main", &applied, &present).is_ok());
    }

    #[test]
    fn a_migration_inserted_below_the_landed_high_water_mark_is_rejected() {
        let applied = [migration("0001_init.sql"), migration("0003_more.sql")];
        let present = [
            migration("0001_init.sql"),
            migration("0002_inserted.sql"),
            migration("0003_more.sql"),
        ];

        let error = validate_catalogue("origin/main", &applied, &present)
            .expect_err("an inserted migration must fail")
            .to_string();
        assert!(error.contains("0002_inserted.sql"), "{error}");
        assert!(error.contains("0003_more.sql"), "{error}");
    }

    #[test]
    fn a_misnamed_sql_file_is_rejected() {
        let applied = [migration("0001_init.sql")];
        let present = [migration("0001_init.sql"), migration("2_wrong.sql")];

        let error = validate_catalogue("main", &applied, &present)
            .expect_err("a misnamed migration must fail")
            .to_string();
        assert!(error.contains("NNNN_lower_snake_case.sql"), "{error}");
        assert!(error.contains("2_wrong.sql"), "{error}");
    }
}
