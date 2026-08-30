//! Where a string literal ends, per language. The scanner calls these so a
//! comment marker inside quotes is skipped rather than captured. Each one
//! returns the index just past the literal, or the end of the input when the
//! literal never closes — an unterminated string ends the file, not the scan.

pub(super) fn quoted_end(
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

pub(super) fn triple_quote_end(bytes: &[u8], start: usize) -> usize {
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

pub(super) fn delimited_end(bytes: &[u8], start: usize, delimiter: &[u8]) -> usize {
    let content_start = start + delimiter.len();
    find(&bytes[content_start..], delimiter).map_or(bytes.len(), |offset| {
        content_start + offset + delimiter.len()
    })
}

pub(super) fn rust_char_end(bytes: &[u8], start: usize) -> Option<usize> {
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

pub(super) fn rust_raw_string_end(bytes: &[u8], start: usize) -> Option<usize> {
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

pub(super) fn find(bytes: &[u8], needle: &[u8]) -> Option<usize> {
    (0..bytes.len().saturating_sub(needle.len() - 1)).find(|&index| starts(bytes, index, needle))
}

pub(super) fn skip_horizontal_space(bytes: &[u8], mut index: usize) -> usize {
    while matches!(bytes.get(index), Some(b' ' | b'\t')) {
        index += 1;
    }
    index
}

pub(super) fn starts(bytes: &[u8], index: usize, needle: &[u8]) -> bool {
    bytes.get(index..index + needle.len()) == Some(needle)
}
