import Foundation
import OndKit

/// The techniques the database is actually seeded with, read through the same
/// accessor the apps read. A test that built its own stages would be a claim
/// about a fixture that happens to resemble the catalogue — "coherent
/// breathing and bellows breath must not draw the same picture" is only worth
/// asserting about the real ones, and a reseed is what this should notice.
enum SeededCatalogue {
    static var techniques: [Technique] {
        CatalogueExport.bundled.techniques
    }

    /// The one technique a test names directly. Everything else is looked up by
    /// the shape of its stages, so the catalogue can grow without touching them.
    static func technique(_ slug: String) -> Technique {
        guard let technique = techniques.first(where: { $0.slug == slug }) else {
            fatalError("`\(slug)` is not in the seeded catalogue")
        }
        return technique
    }

    /// A seeded technique laid out on a session's time axis, at its curated
    /// rounds — the form every test that asks what a *beat* says needs.
    static func timeline(_ slug: String) -> SessionTimeline {
        SessionTimeline(technique: technique(slug))
    }

    /// The figure a stage is drawn in, from the seeded technique. One figure
    /// per stage, so the two numberings agree by construction.
    static func figure(_ slug: String, stage: Int = 0) -> TechniqueFigure {
        let figures = TechniqueFigure.all(for: technique(slug))
        guard figures.indices.contains(stage) else {
            fatalError("`\(slug)` draws no figure for stage \(stage)")
        }
        return figures[stage]
    }

    /// Where the retention sits in the Wim Hof-style rounds — the catalogue's
    /// one open-ended stage. Looked up rather than written down: the
    /// retention moves whenever the protocol around it gains a phase, and a
    /// hardcoded index goes on passing while asserting about whichever stage
    /// took its place.
    static var retention: Int {
        let stages = technique("wim-hof-rounds").stages
        guard let index = stages.firstIndex(where: \.openEnded) else {
            fatalError("the Wim Hof-style rounds have no open-ended stage")
        }
        return index
    }

    /// Every point a figure's strokes pass through, for measuring a silhouette
    /// without caring which command drew it. The baseline is left out: it is
    /// reference rather than subject, and it spans the full width whatever the
    /// line inside it does.
    static func points(of figure: TechniqueFigure) -> [CGPoint] {
        figure.strokes.filter { $0.ink != .baseline }.flatMap { stroke in
            stroke.commands.map { command in
                switch command {
                case let .move(point), let .line(point): point
                case let .curve(point, _, _): point
                }
            }
        }
    }
}
