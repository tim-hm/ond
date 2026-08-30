//! A single pass that carries the line number with it. Every branch that
//! consumes bytes counts the newlines it passed, so a block reports the line it
//! starts on in the source. A branch that forgets to count moves every later
//! block's reported position without failing anything.

use std::path::Path;

use super::lex::{
    delimited_end, find, quoted_end, rust_char_end, rust_raw_string_end, skip_horizontal_space,
    starts, triple_quote_end,
};

/// One contiguous comment block: where it starts, and its text with the
/// comment markers stripped.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommentBlock {
    pub start_line: usize,
    pub content: String,
}

#[derive(Clone, Copy)]
pub(super) enum Language {
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

pub fn blocks(path: &Path, text: &str) -> Vec<CommentBlock> {
    match language(path) {
        None => Vec::new(),
        Some(Language::Markup) => scan_markup(text),
        Some(language) => scan(text, language),
    }
}

pub(super) fn language(path: &Path) -> Option<Language> {
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
}
