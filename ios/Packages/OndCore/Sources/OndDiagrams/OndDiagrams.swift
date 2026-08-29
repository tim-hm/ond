import Foundation
import OndKit

/// Redraws the marketing site's technique drawings from the same
/// `TechniqueFigure` geometry the apps draw and writes them into the
/// committed HTML — `mise run generate:diagrams`, pinned by `check:diagrams`.
/// Only what sits between a slug's markers is rewritten; captions and copy
/// stay hand-written. Usage: `OndDiagrams <catalogue.json> <index.html>`
@main
enum OndDiagrams {
    static func main() {
        // Every kind of drawing the page can ask for, paired with what draws
        // it. Local rather than a static: a stored closure is not `Sendable`,
        // and nothing outside this call has any use for the pairing.
        let drawings: [(vocabulary: Markers.Vocabulary, render: (Technique) -> String)] = [
            (SVG.vocabulary, SVG.figure(for:)),
            (Plot.vocabulary, Plot.svg(for:)),
        ]

        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fail("usage: OndDiagrams <catalogue.json> <index.html>")
        }

        let catalogue = URL(filePath: arguments[1])
        let page = URL(filePath: arguments[2])

        do {
            let techniques = try CatalogueExport.techniques(at: catalogue)
            var html = try String(contentsOf: page, encoding: .utf8)
            var redrawn = 0

            for (vocabulary, render) in drawings {
                var drawn: Set<String> = []

                for technique in techniques {
                    guard let markers = Markers(slug: technique.slug, of: vocabulary, in: html)
                    else { continue }
                    html.replaceSubrange(markers.between, with: render(technique))
                    drawn.insert(technique.slug)
                }

                // A marker naming a slug the catalogue no longer has is the
                // failure worth shouting about: the page keeps drawing a
                // technique that has been renamed or removed, the drawing is
                // never rewritten again, and no diff appears for
                // `check:diagrams` to fail on.
                let orphans = vocabulary.slugs(in: html).subtracting(drawn)
                guard orphans.isEmpty else {
                    fail(
                        "\(page.path) has generated:\(vocabulary.kind) markers for "
                            + "\(orphans.sorted().joined(separator: ", ")), which the catalogue "
                            + "does not hold — rename the marker or drop the drawing"
                    )
                }

                redrawn += drawn.count
            }

            guard redrawn > 0 else {
                fail("no generated drawing markers in \(page.path) — nothing to redraw")
            }

            try html.write(to: page, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(
                Data("redrew \(redrawn) drawings in \(page.lastPathComponent)\n".utf8)
            )
        } catch {
            fail("\(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OndDiagrams: \(message)\n".utf8))
        exit(1)
    }
}
