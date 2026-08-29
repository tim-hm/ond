//! Comment extraction for the prose-length check.
//!
//! The scanner skips quoted strings and returns adjacent full-line comments
//! as one block, across the hand-written formats in this repository.

use std::collections::BTreeSet;
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
    /// `//` and `/* */` over Swift, protobuf, TypeScript, and River.
    Slash,
    Sql,
    /// `#` to end of line over TOML, shell, YAML, and Dockerfiles.
    Hash,
    /// `OpenTofu` supports both hash and slash comments.
    Hcl,
    /// Block comments only, as used by CSS.
    Block,
    /// XML and HTML `<!-- -->` comments.
    Markup,
}

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

pub fn blocks(path: &Path, text: &str) -> Vec<CommentBlock> {
    match language(path) {
        None => Vec::new(),
        Some(Language::Markup) => scan_markup(text),
        Some(language) => scan(text, language),
    }
}

fn language(path: &Path) -> Option<Language> {
    if path.file_name().and_then(|name| name.to_str()) == Some("Dockerfile") {
        return Some(Language::Hash);
    }
    match path.extension()?.to_str()? {
        "rs" => Some(Language::Rust),
        "swift" | "proto" | "river" | "ts" => Some(Language::Slash),
        "sql" => Some(Language::Sql),
        "toml" | "sh" | "yml" | "yaml" | "tmpl" => Some(Language::Hash),
        "tf" => Some(Language::Hcl),
        "css" => Some(Language::Block),
        "html" | "plist" | "xcprivacy" | "svg" => Some(Language::Markup),
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

        if matches!(language, Language::Hash)
            && line == 1
            && index == 0
            && starts(bytes, index, b"#!")
        {
            index = line_end(bytes, index);
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
            Language::Hash if starts(bytes, index, b"\"\"\"") => {
                Some(delimited_end(bytes, index, b"\"\"\""))
            }
            Language::Hash if starts(bytes, index, b"'''") => {
                Some(delimited_end(bytes, index, b"'''"))
            }
            Language::Hash | Language::Hcl if matches!(bytes[index], b'"' | b'\'') => {
                Some(quoted_end(bytes, index, bytes[index], false, false))
            }
            Language::Block if matches!(bytes[index], b'"' | b'\'') => {
                Some(quoted_end(bytes, index, bytes[index], true, false))
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

        if supports_block_comments(language) && starts(bytes, index, b"/*") {
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
    let joins_following = bytes[line_start(bytes, start)..start]
        .iter()
        .all(u8::is_ascii_whitespace);
    let end = loop {
        let content_start = marker + marker_len;
        let line_end = bytes[content_start..]
            .iter()
            .position(|byte| *byte == b'\n')
            .map_or(bytes.len(), |offset| content_start + offset);
        let content = &text[content_start..line_end];
        let content = if matches!(language, Language::Hash | Language::Hcl) && marker_len == 1 {
            content.strip_prefix(' ').unwrap_or(content)
        } else {
            content
        };
        parts.push(content);
        if line_end == bytes.len() {
            break line_end;
        }

        line += 1;
        let next_start = line_end + 1;
        let next_marker = skip_horizontal_space(bytes, next_start);
        if joins_following && line_marker(bytes, next_marker, language) == Some(marker_len) {
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
        Language::Sql | Language::Hash | Language::Hcl | Language::Block | Language::Markup => {
            false
        }
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
        if matches!(language, Language::Rust | Language::Slash) && starts(bytes, index, b"/*") {
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
    match language {
        Language::Sql => starts(bytes, index, b"--").then_some(2),
        Language::Hash => (bytes.get(index) == Some(&b'#')).then_some(1),
        Language::Hcl if bytes.get(index) == Some(&b'#') => Some(1),
        Language::Rust | Language::Slash | Language::Hcl if starts(bytes, index, b"//") => {
            match bytes.get(index + 2) {
                Some(b'/' | b'!') => Some(3),
                _ => Some(2),
            }
        }
        Language::Rust | Language::Slash | Language::Hcl | Language::Block | Language::Markup => {
            None
        }
    }
}

fn supports_block_comments(language: Language) -> bool {
    matches!(
        language,
        Language::Rust | Language::Slash | Language::Sql | Language::Hcl | Language::Block
    )
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

fn delimited_end(bytes: &[u8], start: usize, delimiter: &[u8]) -> usize {
    let content_start = start + delimiter.len();
    find(&bytes[content_start..], delimiter).map_or(bytes.len(), |offset| {
        content_start + offset + delimiter.len()
    })
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

fn scan_markup(text: &str) -> Vec<CommentBlock> {
    let bytes = text.as_bytes();
    let mut found = Vec::new();
    let mut index = 0;
    let mut line = 1;
    while let Some(offset) = find(&bytes[index..], b"<!--") {
        let start = index + offset;
        line += count_newlines(&bytes[index..start]);
        let content_start = start + 4;
        let (content_end, end) = find(&bytes[content_start..], b"-->")
            .map_or((bytes.len(), bytes.len()), |end| {
                (content_start + end, content_start + end + 3)
            });
        found.push(CommentBlock {
            start_line: line,
            content: text[content_start..content_end].to_owned(),
        });
        line += count_newlines(&bytes[start..end]);
        index = end;
    }
    found
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

fn line_start(bytes: &[u8], index: usize) -> usize {
    bytes[..index]
        .iter()
        .rposition(|byte| *byte == b'\n')
        .map_or(0, |position| position + 1)
}

fn line_end(bytes: &[u8], index: usize) -> usize {
    bytes[index..]
        .iter()
        .position(|byte| *byte == b'\n')
        .map_or(bytes.len(), |offset| index + offset)
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
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].content, "real");
        assert_eq!(found[0].start_line, 1);
        assert_eq!(found[1].content, "real");
    }

    #[test]
    fn a_shell_shebang_is_not_a_comment_block() {
        let source = "#!/bin/sh\n# real\nset -eu\necho '# no'\n";
        let found = parsed("a.sh", source);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].content, "real");
        assert_eq!(found[0].start_line, 2);
    }

    #[test]
    fn inline_hash_comments_are_scanned_but_strings_are_not() {
        let source = "value = \"# no\" # one\nother = '# no'\n# two\n";
        let found = parsed("a.toml", source);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].content, "one");
        assert_eq!(found[0].start_line, 1);
        assert_eq!(found[1].content, "two");
        assert_eq!(found[1].start_line, 3);
    }

    #[test]
    fn hcl_slash_and_hash_comments_are_scanned() {
        let source = "# one\nvalue = \"// no\" // two\n/* three */\n";
        let found = parsed("a.tf", source);
        assert_eq!(found.len(), 3);
        assert_eq!(found[0].content, "one");
        assert_eq!(found[1].content, " two");
        assert_eq!(found[2].content, " three ");
    }

    #[test]
    fn css_and_markup_comments_are_scanned() {
        assert_eq!(parsed("a.css", "/* one */")[0].content, " one ");
        assert_eq!(parsed("a.html", "<p>x</p><!-- two -->")[0].content, " two ");
    }

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
