//! Comment extraction for the prose-length check.
//!
//! The scanner skips quoted strings and returns adjacent full-line comments
//! as one block, across the hand-written formats this repository checks:
//! Rust, Swift, protobuf, SQL, and the hash-commented configs.

use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::git;

pub mod length;

/// One contiguous comment block: where it starts, and its text with the
/// comment markers stripped.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommentBlock {
    pub start_line: usize,
    pub content: String,
}

#[derive(Clone, Copy)]
enum Language {
    Rust,
    /// `//` and `/* */` over Swift and protobuf, including Swift's `"""`.
    Slash,
    Sql,
    /// `#` to end of line: TOML, shell, YAML. Tracks TOML `'''`/`"""`
    /// multi-line strings so a `#` inside a mise `run` block is not a comment.
    Hash,
}

const EXTENSIONS: &[&str] = &[
    "rs", "swift", "proto", "sql", "toml", "sh", "yml", "yaml", "tmpl",
];

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
    let mut found: Vec<PathBuf> = tracked
        .lines()
        .chain(untracked.lines())
        .filter(|path| {
            Path::new(path)
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| EXTENSIONS.contains(&extension))
        })
        .filter(|path| !skipped(path))
        .map(|path| repo.join(path))
        .collect();
    found.sort();
    Ok(found)
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

pub fn blocks(path: &Path, text: &str) -> Vec<CommentBlock> {
    match language(path) {
        None => Vec::new(),
        Some(Language::Hash) => scan_hash(text),
        Some(language) => scan(text, language),
    }
}

fn language(path: &Path) -> Option<Language> {
    match path.extension()?.to_str()? {
        "rs" => Some(Language::Rust),
        "swift" | "proto" => Some(Language::Slash),
        "sql" => Some(Language::Sql),
        "toml" | "sh" | "yml" | "yaml" | "tmpl" => Some(Language::Hash),
        _ => None,
    }
}

fn scan(text: &str, language: Language) -> Vec<CommentBlock> {
    let bytes = text.as_bytes();
    let mut found = Vec::new();
    let mut index = 0;
    let mut line = 1;

    while index < bytes.len() {
        if matches!(language, Language::Rust)
            && let Some(end) = rust_raw_string_end(bytes, index)
        {
            line += count_newlines(&bytes[index..end]);
            index = end;
            continue;
        }

        let quote_end = match language {
            Language::Rust if bytes[index] == b'"' => {
                Some(quoted_end(bytes, index, b'"', false, false))
            }
            Language::Rust if bytes[index] == b'\'' => rust_char_end(bytes, index),
            Language::Slash if starts(bytes, index, b"\"\"\"") => {
                Some(triple_quote_end(bytes, index))
            }
            Language::Slash if matches!(bytes[index], b'"' | b'\'') => {
                Some(quoted_end(bytes, index, bytes[index], false, false))
            }
            Language::Sql if matches!(bytes[index], b'"' | b'\'') => {
                Some(quoted_end(bytes, index, bytes[index], true, true))
            }
            _ => None,
        };
        if let Some(end) = quote_end {
            line += count_newlines(&bytes[index..end]);
            index = end;
            continue;
        }

        if let Some(marker_len) = line_marker(bytes, index, language) {
            let (block, end, next_line) = line_block(text, index, line, marker_len, language);
            found.push(block);
            index = end;
            line = next_line;
            continue;
        }

        if starts(bytes, index, b"/*") {
            let (block, end, next_line) = block_comment(text, index, line, language);
            found.push(block);
            index = end;
            line = next_line;
            continue;
        }

        if bytes[index] == b'\n' {
            line += 1;
        }
        index += 1;
    }
    found
}

fn line_block(
    text: &str,
    start: usize,
    start_line: usize,
    marker_len: usize,
    language: Language,
) -> (CommentBlock, usize, usize) {
    let bytes = text.as_bytes();
    let mut parts = Vec::new();
    let mut marker = start;
    let mut line = start_line;
    let end = loop {
        let content_start = marker + marker_len;
        let line_end = bytes[content_start..]
            .iter()
            .position(|byte| *byte == b'\n')
            .map_or(bytes.len(), |offset| content_start + offset);
        parts.push(&text[content_start..line_end]);
        if line_end == bytes.len() {
            break line_end;
        }

        line += 1;
        let next_start = line_end + 1;
        let next_marker = skip_horizontal_space(bytes, next_start);
        if line_marker(bytes, next_marker, language) == Some(marker_len) {
            marker = next_marker;
            continue;
        }
        break next_start;
    };

    (
        CommentBlock {
            start_line,
            content: parts.join("\n"),
        },
        end,
        line,
    )
}

fn block_comment(
    text: &str,
    start: usize,
    start_line: usize,
    language: Language,
) -> (CommentBlock, usize, usize) {
    let bytes = text.as_bytes();
    let doc = match language {
        Language::Rust => matches!(bytes.get(start + 2), Some(b'*' | b'!')),
        Language::Slash => bytes.get(start + 2) == Some(&b'*'),
        Language::Sql | Language::Hash => false,
    };
    let marker_len = if doc { 3 } else { 2 };
    let mut index = start + marker_len;
    let mut depth = 1;
    let mut line = start_line;
    let mut content_end = bytes.len();

    while index < bytes.len() {
        // Only Rust nests block comments; Swift does too, and sharing Rust's
        // rule here is right for both members of Slash except protobuf, where
        // an unmatched inner `/*` inside a comment is vanishingly rare.
        if !matches!(language, Language::Sql) && starts(bytes, index, b"/*") {
            depth += 1;
            index += 2;
            continue;
        }
        if starts(bytes, index, b"*/") {
            depth -= 1;
            if depth == 0 {
                content_end = index;
                index += 2;
                break;
            }
            index += 2;
            continue;
        }
        if bytes[index] == b'\n' {
            line += 1;
        }
        index += 1;
    }

    (
        CommentBlock {
            start_line,
            content: text[start + marker_len..content_end].to_owned(),
        },
        index,
        line,
    )
}

fn line_marker(bytes: &[u8], index: usize, language: Language) -> Option<usize> {
    if matches!(language, Language::Sql) {
        return starts(bytes, index, b"--").then_some(2);
    }
    if !starts(bytes, index, b"//") {
        return None;
    }
    match bytes.get(index + 2) {
        Some(b'/' | b'!') => Some(3),
        _ => Some(2),
    }
}

fn quoted_end(
    bytes: &[u8],
    start: usize,
    quote: u8,
    allow_newline: bool,
    doubled_escape: bool,
) -> usize {
    let mut index = start + 1;
    while index < bytes.len() {
        if bytes[index] == b'\n' && !allow_newline {
            return index;
        }
        if doubled_escape && bytes[index] == quote && bytes.get(index + 1) == Some(&quote) {
            index += 2;
            continue;
        }
        if bytes[index] == quote {
            return index + 1;
        }
        if !doubled_escape && bytes[index] == b'\\' {
            index = (index + 2).min(bytes.len());
        } else {
            index += 1;
        }
    }
    bytes.len()
}

fn triple_quote_end(bytes: &[u8], start: usize) -> usize {
    let mut index = start + 3;
    while index < bytes.len() {
        if bytes[index] == b'\\' {
            index = (index + 2).min(bytes.len());
            continue;
        }
        if starts(bytes, index, b"\"\"\"") {
            return index + 3;
        }
        index += 1;
    }
    bytes.len()
}

fn rust_char_end(bytes: &[u8], start: usize) -> Option<usize> {
    let mut index = start + 1;
    while index < bytes.len() && bytes[index] != b'\n' {
        if bytes[index] == b'\\' {
            index = (index + 2).min(bytes.len());
        } else if bytes[index] == b'\'' {
            return Some(index + 1);
        } else {
            index += 1;
        }
    }
    None
}

fn rust_raw_string_end(bytes: &[u8], start: usize) -> Option<usize> {
    let mut index = start;
    if bytes.get(index) == Some(&b'b') {
        index += 1;
    }
    if bytes.get(index) != Some(&b'r') {
        return None;
    }
    index += 1;
    let hashes_start = index;
    while bytes.get(index) == Some(&b'#') {
        index += 1;
    }
    if bytes.get(index) != Some(&b'"') {
        return None;
    }
    let hashes = index - hashes_start;
    index += 1;
    while index < bytes.len() {
        if bytes[index] == b'"'
            && bytes.get(index + 1..index + 1 + hashes)
                == Some(&bytes[hashes_start..hashes_start + hashes])
        {
            return Some(index + 1 + hashes);
        }
        index += 1;
    }
    Some(bytes.len())
}

fn scan_hash(text: &str) -> Vec<CommentBlock> {
    let mut found = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    let mut block_start = 0;
    let mut multiline: Option<&'static [u8]> = None;

    let mut flush = |block: &mut Vec<&str>, start: usize| {
        if !block.is_empty() {
            found.push(CommentBlock {
                start_line: start,
                content: block.join("\n"),
            });
            block.clear();
        }
    };

    for (index, line) in text.lines().enumerate() {
        let number = index + 1;
        if let Some(delimiter) = multiline {
            multiline = match find(line.as_bytes(), delimiter) {
                Some(end) => string_open(&line.as_bytes()[end + delimiter.len()..]),
                None => multiline,
            };
            continue;
        }

        let trimmed = line.trim_start();
        let shebang = number == 1 && trimmed.starts_with("#!");
        if trimmed.starts_with('#') && !shebang {
            if block.is_empty() {
                block_start = number;
            }
            let content = trimmed.strip_prefix('#').unwrap_or(trimmed);
            block.push(content.strip_prefix(' ').unwrap_or(content));
            continue;
        }

        flush(&mut block, block_start);
        multiline = string_open(line.as_bytes());
    }
    flush(&mut block, block_start);
    found
}

/// Whether a multi-line TOML string opens on this line and does not close.
fn string_open(bytes: &[u8]) -> Option<&'static [u8]> {
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'#' => return None,
            quote @ (b'\'' | b'"') => {
                let delimiter: &'static [u8] = if quote == b'\'' { b"'''" } else { b"\"\"\"" };
                if starts(bytes, index, delimiter) {
                    match find(&bytes[index + 3..], delimiter) {
                        Some(offset) => index += 3 + offset + 3,
                        None => return Some(delimiter),
                    }
                } else {
                    index = quoted_end(bytes, index, quote, false, false);
                }
            }
            _ => index += 1,
        }
    }
    None
}

fn find(bytes: &[u8], needle: &[u8]) -> Option<usize> {
    (0..bytes.len().saturating_sub(needle.len() - 1)).find(|&index| starts(bytes, index, needle))
}

fn skip_horizontal_space(bytes: &[u8], mut index: usize) -> usize {
    while matches!(bytes.get(index), Some(b' ' | b'\t')) {
        index += 1;
    }
    index
}

fn starts(bytes: &[u8], index: usize, needle: &[u8]) -> bool {
    bytes.get(index..index + needle.len()) == Some(needle)
}

fn count_newlines(bytes: &[u8]) -> usize {
    bytes.split(|byte| *byte == b'\n').count() - 1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(name: &str, source: &str) -> Vec<CommentBlock> {
        blocks(Path::new(name), source)
    }

    #[test]
    fn adjacent_line_comments_are_one_block() {
        let found = parsed("a.rs", "// one\n// two\nlet x = 1; // three\n");
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].content, " one\n two");
        assert_eq!(found[0].start_line, 1);
    }

    #[test]
    fn doc_lines_do_not_join_plain_lines() {
        let found = parsed("a.rs", "/// doc\n// plain\n");
        assert_eq!(found.len(), 2);
    }

    #[test]
    fn comment_shapes_inside_strings_are_ignored() {
        let source = "let a = \"// no\";\n/* yes */\n";
        let found = parsed("a.rs", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, " yes ");
    }

    #[test]
    fn rust_raw_strings_and_lifetimes_are_not_comments() {
        let source = "const X: &str = r#\"// no\"#;\nfn f<'a>(x: &'a str) {} // yes\n";
        let found = parsed("a.rs", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, " yes");
    }

    #[test]
    fn swift_multiline_strings_are_not_comments() {
        let source = "let s = \"\"\"\n// no\n# no\n\"\"\"\n/// yes\n";
        let found = parsed("a.swift", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, " yes");
    }

    #[test]
    fn sql_line_comments_are_grouped() {
        let found = parsed("a.sql", "-- one\n-- two\nSELECT '-- no';\n");
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, " one\n two");
    }

    #[test]
    fn a_hash_inside_a_toml_multiline_string_is_not_a_comment() {
        let source = "# real\n[tasks.x]\nrun = '''\n# not a comment\necho hi\n'''\n# also real\n";
        let found = parsed("a.toml", source);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].content, "real");
        assert_eq!(found[1].content, "also real");
        assert_eq!(found[1].start_line, 7);
    }

    #[test]
    fn a_toml_multiline_string_closing_and_reopening_on_one_line_tracks() {
        let source = "a = '''x''' # real\nb = '''\n# not\n''' \n# real\n";
        let found = parsed("a.toml", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, "real");
    }

    #[test]
    fn a_shell_shebang_is_not_a_comment_block() {
        let source = "#!/bin/sh\n# real\nset -eu\necho '# no'\n";
        let found = parsed("a.sh", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, "real");
        assert_eq!(found[0].start_line, 2);
    }
}
