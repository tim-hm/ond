//! The prose-comment cap and its waiver ledger.
//!
//! The baseline identifies pre-cap blocks by path and content, so editing a
//! waived block or moving its file drops the waiver instead of extending it.
//! A row matching no block fails; `mise run comments:baseline` rebuilds.

use std::collections::BTreeMap;
use std::path::Path;

use anyhow::{Context, Result, bail};
use ring::digest;

use super::{CommentBlock, blocks, files, relative};

const MAX_LINES: usize = 5;
const MAX_CHARS: usize = 400;
const BASELINE_PATH: &str = "crates/toolkit/comment-length-baseline.tsv";
const BASELINE: &str = include_str!("../../comment-length-baseline.tsv");

/// Prefixes the cap never binds: deleting one breaks the build, silences a
/// real warning, or erases an unresolved task.
const PROTECTED: &[&str] = &[
    "SAFETY:",
    "TODO",
    "FIXME",
    "#[allow(",
    "swiftlint:",
    "swiftformat:",
    "shellcheck",
];

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
struct Key {
    path: String,
    hash: String,
}

#[derive(Clone, Debug)]
struct Oversized {
    line: usize,
    lines: usize,
    chars: usize,
}

#[allow(
    clippy::print_stdout,
    reason = "the waived count is the success output"
)]
pub fn check(repo: &Path) -> Result<()> {
    let expected = parse_baseline(BASELINE)?;
    let found = inventory(repo)?;

    let mut failures = Vec::new();
    for (key, block) in unbaselined(&found, &expected) {
        failures.push(format!(
            "{}:{}: prose comment has {} content lines and {} characters; maximum is {MAX_LINES} lines or {MAX_CHARS} characters",
            key.path, block.line, block.lines, block.chars
        ));
    }
    for key in stale(&found, &expected) {
        failures.push(format!(
            "{BASELINE_PATH}: stale baseline entry; remove this line -> {}\t{}",
            key.path, key.hash
        ));
    }

    if failures.is_empty() {
        let waived: usize = expected.values().sum();
        if waived > 0 {
            println!("check:comments: {waived} block(s) still waived in {BASELINE_PATH}");
        }
        return Ok(());
    }
    bail!(
        "check:comments: {} finding(s); bring each block under the cap, or waive it deliberately with `mise run comments:baseline`:\n{}",
        failures.len(),
        failures.join("\n")
    )
}

/// Rewrite the baseline from the current tree. Every row it writes waives a
/// block, so review the diff before committing it.
#[allow(
    clippy::print_stdout,
    reason = "the summary is the subcommand's output"
)]
pub fn write_baseline(repo: &Path) -> Result<()> {
    let found = inventory(repo)?;
    let path = repo.join(BASELINE_PATH);
    std::fs::write(&path, render_baseline(&found))
        .with_context(|| format!("write {}", path.display()))?;
    println!(
        "{BASELINE_PATH}: {} row(s), {} block(s) waived",
        found.len(),
        found.values().map(Vec::len).sum::<usize>()
    );
    Ok(())
}

fn inventory(repo: &Path) -> Result<BTreeMap<Key, Vec<Oversized>>> {
    let mut found: BTreeMap<Key, Vec<Oversized>> = BTreeMap::new();
    for path in files(repo)? {
        let text =
            std::fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?;
        let shown = relative(repo, &path);
        for block in blocks(&path, &text) {
            let Some((content, lines, chars)) = measure(&block) else {
                continue;
            };
            if lines <= MAX_LINES && chars <= MAX_CHARS {
                continue;
            }
            let key = Key {
                path: shown.clone(),
                hash: content_hash(&content),
            };
            found.entry(key).or_default().push(Oversized {
                line: block.start_line,
                lines,
                chars,
            });
        }
    }
    Ok(found)
}

fn unbaselined<'a>(
    found: &'a BTreeMap<Key, Vec<Oversized>>,
    expected: &BTreeMap<Key, usize>,
) -> Vec<(&'a Key, &'a Oversized)> {
    found
        .iter()
        .flat_map(|(key, blocks)| {
            let allowed = expected.get(key).copied().unwrap_or(0);
            blocks.iter().skip(allowed).map(move |block| (key, block))
        })
        .collect()
}

/// Baseline rows the tree no longer justifies. A waiver outlives its block
/// when the file is deleted or moved, or the comment edited; a row waiving
/// more copies than exist pre-authorises the next copy.
fn stale<'a>(
    found: &BTreeMap<Key, Vec<Oversized>>,
    expected: &'a BTreeMap<Key, usize>,
) -> Vec<&'a Key> {
    expected
        .iter()
        .filter(|(key, allowed)| found.get(*key).map_or(0, Vec::len) < **allowed)
        .map(|(key, _)| key)
        .collect()
}

fn render_baseline(found: &BTreeMap<Key, Vec<Oversized>>) -> String {
    let rows = found
        .iter()
        .map(|(key, blocks)| format!("{}\t{}\t{}\n", key.path, key.hash, blocks.len()));
    std::iter::once("# path\tnormalized-content-sha256\toccurrences\n".to_owned())
        .chain(rows)
        .collect()
}

/// Normalised content, content lines, and characters — or `None` for a block
/// the cap does not bind.
fn measure(block: &CommentBlock) -> Option<(String, usize, usize)> {
    let mut lines: Vec<String> = block
        .content
        .lines()
        .map(|line| {
            let trimmed = line.trim();
            trimmed
                .strip_prefix('*')
                .unwrap_or(trimmed)
                .trim()
                .to_owned()
        })
        .collect();
    while lines.first().is_some_and(String::is_empty) {
        lines.remove(0);
    }
    while lines.last().is_some_and(String::is_empty) {
        lines.pop();
    }
    if lines.is_empty() {
        return None;
    }
    let first = lines[0].trim_start();
    if PROTECTED.iter().any(|prefix| first.starts_with(prefix)) {
        return None;
    }
    let content = lines.join("\n");
    let chars = content.chars().count();
    Some((content, lines.len(), chars))
}

fn content_hash(content: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let digest = digest::digest(&digest::SHA256, content.as_bytes());
    let mut result = String::with_capacity(digest.as_ref().len() * 2);
    for byte in digest.as_ref() {
        result.push(HEX[usize::from(byte >> 4)] as char);
        result.push(HEX[usize::from(byte & 0x0f)] as char);
    }
    result
}

fn parse_baseline(text: &str) -> Result<BTreeMap<Key, usize>> {
    let mut entries = BTreeMap::new();
    let mut previous: Option<Key> = None;
    for (index, line) in text.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let (Some(path), Some(hash), Some(count), None) =
            (fields.next(), fields.next(), fields.next(), fields.next())
        else {
            bail!(
                "{BASELINE_PATH}:{}: expected path, hash, and count",
                index + 1
            );
        };
        let key = Key {
            path: path.to_owned(),
            hash: hash.to_owned(),
        };
        if previous.as_ref().is_some_and(|item| item >= &key) {
            bail!(
                "{BASELINE_PATH}:{}: entries must be unique and sorted",
                index + 1
            );
        }
        let count: usize = count
            .parse()
            .with_context(|| format!("{BASELINE_PATH}:{}: invalid count", index + 1))?;
        if count == 0 {
            bail!("{BASELINE_PATH}:{}: count must be positive", index + 1);
        }
        previous = Some(key.clone());
        entries.insert(key, count);
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(content: &str) -> CommentBlock {
        CommentBlock {
            start_line: 1,
            content: content.to_owned(),
        }
    }

    #[test]
    fn exact_limits_pass() {
        let five_lines = "one\ntwo\nthree\nfour\nfive";
        let four_hundred = "x".repeat(400);
        assert_eq!(measure(&block(five_lines)).unwrap().1, 5);
        assert_eq!(measure(&block(&four_hundred)).unwrap().2, 400);
    }

    #[test]
    fn excess_lines_and_unicode_characters_are_measured() {
        let six_lines = "one\ntwo\nthree\nfour\nfive\nsix";
        let unicode = "é".repeat(401);
        assert_eq!(measure(&block(six_lines)).unwrap().1, 6);
        assert_eq!(measure(&block(&unicode)).unwrap().2, 401);
    }

    #[test]
    fn directives_are_exempt() {
        for directive in ["SAFETY:", "TODO", "FIXME", "swiftlint:", "swiftformat:"] {
            assert!(measure(&block(&format!("{directive} {}", "x".repeat(500)))).is_none());
        }
    }

    #[test]
    fn baseline_requires_sorted_unique_positive_counts() {
        assert!(parse_baseline("b\thash\t1\na\thash\t1\n").is_err());
        assert!(parse_baseline("a\thash\t1\na\thash\t1\n").is_err());
        assert!(parse_baseline("a\thash\t0\n").is_err());
        assert_eq!(
            parse_baseline("a\thash\t2\n").unwrap().values().next(),
            Some(&2)
        );
    }

    #[test]
    fn the_committed_baseline_parses() {
        parse_baseline(BASELINE).unwrap();
    }

    #[test]
    fn a_waiver_with_no_matching_block_is_stale() {
        let key = |path: &str| Key {
            path: path.to_owned(),
            hash: "a".to_owned(),
        };
        let oversized = || Oversized {
            line: 1,
            lines: 6,
            chars: 10,
        };
        let live = key("live.rs");
        let dead = key("gone.rs");
        let found = BTreeMap::from([(live.clone(), vec![oversized()])]);
        let expected = BTreeMap::from([(live.clone(), 1), (dead.clone(), 1)]);
        assert_eq!(stale(&found, &expected), vec![&dead]);

        // A row waiving two copies where one survives is stale by the surplus.
        let over = BTreeMap::from([(live.clone(), 2)]);
        assert_eq!(stale(&found, &over), vec![&live]);
    }

    #[test]
    fn a_rendered_baseline_round_trips() {
        let key = |path: &str| Key {
            path: path.to_owned(),
            hash: "abc".to_owned(),
        };
        let oversized = || Oversized {
            line: 1,
            lines: 6,
            chars: 10,
        };
        let found = BTreeMap::from([
            (key("a.rs"), vec![oversized(), oversized()]),
            (key("b.rs"), vec![oversized()]),
        ]);
        let parsed = parse_baseline(&render_baseline(&found)).unwrap();
        assert_eq!(parsed, BTreeMap::from([(key("a.rs"), 2), (key("b.rs"), 1)]));
    }

    #[test]
    fn occurrence_count_does_not_exempt_an_extra_copy() {
        let key = Key {
            path: "fixture.rs".to_owned(),
            hash: "hash".to_owned(),
        };
        let oversized = || Oversized {
            line: 1,
            lines: 6,
            chars: 10,
        };
        let found = BTreeMap::from([(key.clone(), vec![oversized(), oversized()])]);
        let expected = BTreeMap::from([(key, 1)]);
        assert_eq!(unbaselined(&found, &expected).len(), 1);
    }
}
