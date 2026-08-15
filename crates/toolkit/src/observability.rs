//! Keeps the Swift logging vocabulary equal to the categories production code
//! actually uses.
//!
//! A hand-maintained table had drifted in two consecutive audits. The registry
//! now lives beside the subsystem in `OndKit`; this check reads both sides so a
//! category addition and its vocabulary decision have to arrive together.

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail, ensure};

use crate::sources::source_files;

const IOS_DIR: &str = "ios";
const REGISTRY_PATH: &str = "ios/Packages/OndCore/Sources/OndKit/Log.swift";
/// Shared with `metrics`, which validates the metric table in the same file.
pub const DOCUMENTATION_PATH: &str = "docs/observability.md";
const REGISTRY_DECLARATION: &str = "static let categories: Set<String> = [";
const DOCUMENTATION_TABLE: &str = "| Category";
const CATEGORY_ARGUMENT: &str = "category:";

/// Verifies that the Swift category registry exactly matches production uses.
///
/// Generated code, build products, tests and the package's development-only
/// executables are excluded. The registry file is also excluded from the use
/// side; otherwise its own literals would make every stale entry look active.
pub fn check(repo: &Path) -> Result<()> {
    let registry_path = repo.join(REGISTRY_PATH);
    let source = fs::read_to_string(&registry_path)
        .with_context(|| format!("read Swift logger registry at {}", registry_path.display()))?;
    let registry = parse_registry(&source)?;
    let used = production_categories(repo, &registry_path)?;
    let documentation_path = repo.join(DOCUMENTATION_PATH);
    let documentation = fs::read_to_string(&documentation_path).with_context(|| {
        format!(
            "read observability documentation at {}",
            documentation_path.display()
        )
    })?;
    let documented = parse_documented_categories(&documentation)?;

    validate(&registry, &used)?;
    validate_documentation(&registry, &documented)
}

fn parse_registry(source: &str) -> Result<BTreeSet<String>> {
    let start = source
        .find(REGISTRY_DECLARATION)
        .map(|index| index + REGISTRY_DECLARATION.len())
        .context("check:observability: Log.categories declaration is missing or changed shape")?;
    let tail = &source[start..];
    let end = tail
        .find(']')
        .context("check:observability: Log.categories has no closing bracket")?;

    let mut entries = Vec::new();
    for line in tail[..end]
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
    {
        let literal = line.strip_suffix(',').unwrap_or(line);
        let category = literal
            .strip_prefix('"')
            .and_then(|literal| literal.strip_suffix('"'))
            .with_context(|| {
                format!("check:observability: Log.categories entry is not a string literal: {line}")
            })?;
        ensure_category(category, "Log.categories")?;
        entries.push(category.to_owned());
    }

    ensure!(
        !entries.is_empty(),
        "check:observability: Log.categories must not be empty"
    );
    let registry = entries.iter().cloned().collect::<BTreeSet<_>>();
    ensure!(
        registry.len() == entries.len(),
        "check:observability: Log.categories contains a duplicate"
    );
    ensure!(
        entries.windows(2).all(|pair| pair[0] < pair[1]),
        "check:observability: Log.categories must be sorted"
    );
    Ok(registry)
}

fn parse_documented_categories(source: &str) -> Result<BTreeSet<String>> {
    let table = source
        .find(DOCUMENTATION_TABLE)
        .map(|index| &source[index..])
        .context("check:observability: docs/observability.md has no category table")?;
    let table = table.split("\n\n").next().unwrap_or(table);
    let mut entries = Vec::new();

    for line in table.lines().skip(2).filter(|line| line.starts_with('|')) {
        let cell = line
            .trim_start_matches('|')
            .split('|')
            .next()
            .map(str::trim)
            .context("check:observability: category table row has no first cell")?;
        let category = cell
            .strip_prefix('`')
            .and_then(|cell| cell.strip_suffix('`'))
            .with_context(|| {
                format!("check:observability: documented category is not one code literal: {cell}")
            })?;
        ensure_category(category, "docs/observability.md")?;
        entries.push(category.to_owned());
    }

    ensure!(
        !entries.is_empty(),
        "check:observability: docs/observability.md category table must not be empty"
    );
    let documented = entries.iter().cloned().collect::<BTreeSet<_>>();
    ensure!(
        documented.len() == entries.len(),
        "check:observability: docs/observability.md category table contains a duplicate"
    );
    ensure!(
        entries.windows(2).all(|pair| pair[0] < pair[1]),
        "check:observability: docs/observability.md category table must be sorted"
    );
    Ok(documented)
}

fn production_categories(
    repo: &Path,
    registry_path: &Path,
) -> Result<BTreeMap<String, BTreeSet<PathBuf>>> {
    let swift_files = source_files(&repo.join(IOS_DIR), "swift", &skip_directory)?
        .into_iter()
        .filter(|path| path != registry_path);

    let mut categories = BTreeMap::<String, BTreeSet<PathBuf>>::new();
    for path in swift_files {
        let source = fs::read_to_string(&path)
            .with_context(|| format!("read production Swift source at {}", path.display()))?;
        let relative = path.strip_prefix(repo).unwrap_or(&path).to_path_buf();
        for category in category_literals(&source)? {
            categories
                .entry(category)
                .or_default()
                .insert(relative.clone());
        }
    }

    ensure!(
        !categories.is_empty(),
        "check:observability: no production Swift logger category literals were found"
    );
    Ok(categories)
}

fn skip_directory(path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
        return true;
    };

    name.starts_with('.')
        || name == "build"
        || name == "DerivedData"
        || name == "Generated"
        || name == "OndDiagrams"
        || name == "OndLiveSmoke"
        || name == "Tests"
        || name.ends_with("Tests")
        || name.ends_with(".xcodeproj")
}

fn category_literals(source: &str) -> Result<Vec<String>> {
    let mut categories = Vec::new();
    let mut searched = source;

    while let Some(offset) = searched.find(CATEGORY_ARGUMENT) {
        let previous = searched[..offset].chars().next_back();
        let after_marker = &searched[offset + CATEGORY_ARGUMENT.len()..];
        searched = after_marker;

        if previous.is_some_and(|character| character.is_alphanumeric() || character == '_') {
            continue;
        }

        let candidate = after_marker.trim_start();
        let Some(literal) = candidate.strip_prefix('"') else {
            continue;
        };
        let end = literal
            .find('"')
            .context("check:observability: unterminated Swift logger category string literal")?;
        let category = &literal[..end];
        ensure_category(category, "production Swift")?;
        categories.push(category.to_owned());
        searched = &literal[end + 1..];
    }

    Ok(categories)
}

fn ensure_category(category: &str, source: &str) -> Result<()> {
    ensure!(
        !category.is_empty()
            && category
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-'),
        "check:observability: {source} category `{category}` must use lower-kebab-case"
    );
    Ok(())
}

fn validate(registry: &BTreeSet<String>, used: &BTreeMap<String, BTreeSet<PathBuf>>) -> Result<()> {
    let missing = used
        .iter()
        .filter(|(category, _)| !registry.contains(*category))
        .collect::<Vec<_>>();
    let stale = registry
        .iter()
        .filter(|category| !used.contains_key(*category))
        .collect::<Vec<_>>();

    if missing.is_empty() && stale.is_empty() {
        return Ok(());
    }

    let mut details = Vec::new();
    if !missing.is_empty() {
        details.push("missing from Log.categories:".to_owned());
        details.extend(missing.into_iter().map(|(category, paths)| {
            let locations = paths
                .iter()
                .map(|path| path.display().to_string())
                .collect::<Vec<_>>()
                .join(", ");
            format!("  {category}: {locations}")
        }));
    }
    if !stale.is_empty() {
        details.push("unused by production Swift:".to_owned());
        details.extend(stale.into_iter().map(|category| format!("  {category}")));
    }

    bail!(
        "check:observability: Swift logger category registry does not match production literals:\n{}",
        details.join("\n")
    )
}

fn validate_documentation(
    registry: &BTreeSet<String>,
    documented: &BTreeSet<String>,
) -> Result<()> {
    let undocumented = registry.difference(documented).cloned().collect::<Vec<_>>();
    let stale = documented.difference(registry).cloned().collect::<Vec<_>>();

    if undocumented.is_empty() && stale.is_empty() {
        return Ok(());
    }

    let mut details = Vec::new();
    if !undocumented.is_empty() {
        details.push("missing from docs/observability.md:".to_owned());
        details.extend(
            undocumented
                .into_iter()
                .map(|category| format!("  {category}")),
        );
    }
    if !stale.is_empty() {
        details.push("documented but absent from Log.categories:".to_owned());
        details.extend(stale.into_iter().map(|category| format!("  {category}")));
    }

    bail!(
        "check:observability: documented Swift logger categories do not match Log.categories:\n{}",
        details.join("\n")
    )
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::*;

    static FIXTURE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct Fixture(PathBuf);

    impl Fixture {
        fn new() -> Self {
            let sequence = FIXTURE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "ond-toolkit-observability-{}-{sequence}",
                std::process::id()
            ));
            fs::create_dir_all(&root).unwrap();
            Self(root)
        }

        fn write(&self, relative: &str, source: &str) {
            let path = self.0.join(relative);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, source).unwrap();
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            drop(fs::remove_dir_all(&self.0));
        }
    }

    fn registry(categories: &[&str]) -> BTreeSet<String> {
        categories
            .iter()
            .map(|category| (*category).to_owned())
            .collect()
    }

    fn used(categories: &[(&str, &str)]) -> BTreeMap<String, BTreeSet<PathBuf>> {
        let mut used = BTreeMap::new();
        for (category, path) in categories {
            used.entry((*category).to_owned())
                .or_insert_with(BTreeSet::new)
                .insert(PathBuf::from(path));
        }
        used
    }

    #[test]
    fn extracts_direct_and_store_category_literals() {
        let source = r#"
            let direct = Logger(category: "watch-link")
            let store = JSONFileStore(category: "session-store")
            let dynamic = Logger(category: supplied)
            let unrelated = value(subcategory: "not-a-log")
        "#;

        assert_eq!(
            category_literals(source).unwrap(),
            ["watch-link", "session-store"]
        );
    }

    #[test]
    fn accepts_an_exact_registry() {
        let registry = registry(&["session-store", "watch-link"]);
        let used = used(&[
            ("session-store", "ios/OndKit/FileSessionStore.swift"),
            ("watch-link", "ios/Ond/WatchLink.swift"),
        ]);

        assert!(validate(&registry, &used).is_ok());
    }

    #[test]
    fn rejects_a_duplicate_registry_entry() {
        let source = r#"
            static let categories: Set<String> = [
                "watch-link",
                "watch-link",
            ]
        "#;

        let error = parse_registry(source).unwrap_err().to_string();
        assert!(error.contains("duplicate"), "{error}");
    }

    #[test]
    fn reports_missing_and_stale_categories_together() {
        let registry = registry(&["old-channel", "watch-link"]);
        let used = used(&[
            ("new-channel", "ios/Ond/New.swift"),
            ("watch-link", "ios/Ond/WatchLink.swift"),
        ]);

        let error = validate(&registry, &used).unwrap_err().to_string();
        assert!(error.contains("missing from Log.categories"), "{error}");
        assert!(error.contains("new-channel: ios/Ond/New.swift"), "{error}");
        assert!(error.contains("unused by production Swift"), "{error}");
        assert!(error.contains("old-channel"), "{error}");
    }

    #[test]
    fn excludes_generated_test_and_development_only_literals() {
        let fixture = Fixture::new();
        fixture.write(
            "ios/Ond/App.swift",
            r#"let logger = Logger(category: "production")"#,
        );
        fixture.write(
            "ios/OndAppUITests/AppTests.swift",
            r#"let logger = Logger(category: "tests")"#,
        );
        fixture.write(
            "ios/Packages/OndCore/Sources/OndAPI/Generated/API.swift",
            r#"let logger = Logger(category: "generated")"#,
        );
        fixture.write(
            "ios/Packages/OndCore/Sources/OndDiagrams/Main.swift",
            r#"let logger = Logger(category: "diagrams")"#,
        );
        fixture.write(
            "ios/Packages/OndCore/Sources/OndLiveSmoke/Main.swift",
            r#"let logger = Logger(category: "smoke")"#,
        );

        let categories = production_categories(&fixture.0, &fixture.0.join(REGISTRY_PATH)).unwrap();
        assert_eq!(
            categories.keys().cloned().collect::<Vec<_>>(),
            ["production"]
        );
    }

    #[test]
    fn documented_categories_must_be_single_sorted_literals() {
        let source = r"
| Category | Covers |
| :-- | :-- |
| `account` | Account work |
| `watch-link` | Watch work |

Next paragraph.
        ";

        assert_eq!(
            parse_documented_categories(source).unwrap(),
            registry(&["account", "watch-link"])
        );
    }
}
