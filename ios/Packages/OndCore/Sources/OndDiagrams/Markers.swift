import Foundation

/// Where one technique's generated drawing sits in the page.
///
/// Markers rather than a parsed DOM: the surrounding HTML is hand-written and
/// must survive untouched, and the smallest thing that guarantees that is only
/// ever touching the span between two comments.
struct Markers {
    /// What kind of drawing a pair of markers asks for. The kind is in the
    /// comment itself — `generated:figure`, `generated:plot` — so the page says
    /// which drawing it wants where, and a slug can carry both.
    struct Vocabulary {
        let kind: String

        var opening: String {
            "<!-- generated:\(kind) "
        }

        var closing: String {
            "<!-- /generated:\(kind) -->"
        }

        /// Every slug the page has an opening marker of this kind for, so a
        /// marker naming a technique the catalogue dropped can be reported
        /// rather than skipped.
        func slugs(in html: String) -> Set<String> {
            var slugs: Set<String> = []
            var rest = html[...]

            while let opening = rest.range(of: opening) {
                let after = rest[opening.upperBound...]
                guard let close = after.range(of: " -->") else { break }
                slugs.insert(String(after[..<close.lowerBound]))
                rest = after[close.upperBound...]
            }

            return slugs
        }
    }

    let between: Range<String.Index>

    init?(slug: String, of vocabulary: Vocabulary, in html: String) {
        guard let start = html.range(of: vocabulary.opening + slug + " -->"),
              let end = html.range(
                  of: vocabulary.closing,
                  range: start.upperBound ..< html.endIndex
              )
        else {
            return nil
        }

        between = start.upperBound ..< end.lowerBound
    }
}
