import Foundation
import os

/// The committed `catalogue.json` — the seeded technique catalogue, exported
/// from `crates/migrate` by `mise run generate:catalogue`.
///
/// The catalogue lives in Rust and the geometry that draws it lives here, so
/// something has to cross between the two languages. This crosses it once, into
/// an artefact `mise run check:generated` pins the export of, rather than once
/// per consumer.
///
/// A second decoding path onto `Technique`, alongside the contract's: the app
/// fetches a catalogue over gRPC and caches it, and `Technique`'s `Codable`
/// conformance round-trips *that*, while this reads the Rust seed's field
/// names. Both ship, deliberately — `bundled` below is what a device that has
/// never reached the server breathes.
public enum CatalogueExport {
    private static let logger = Logger(category: "catalogue-export")

    /// The catalogue this build shipped with — the seed
    /// `CachedTechniqueRepository` falls back to when no fetch has ever
    /// succeeded, so a first-ever launch out of range still lists every
    /// technique.
    ///
    /// Empty rather than fatal where the resource is missing or unreadable. It
    /// is a committed artefact pinned by `mise run check:generated` and decoded
    /// by a decoder written for exactly it, so a failure here means the build is
    /// broken — and a broken build should not be a launch crash for everybody
    /// when the honest degradation is the behaviour that predates this seed.
    /// What actually holds the resource to its contents is a test, which costs
    /// nothing to fail and reaches nobody's launch screen.
    public static let bundled: [Technique] = {
        guard let url = Bundle.module.url(forResource: "catalogue", withExtension: "json") else {
            logger.error("no catalogue.json in the bundle — this build ships no seed")
            return []
        }

        do {
            return try techniques(at: url)
        } catch {
            logger
                .error(
                    "the bundled catalogue could not be read: \(error.localizedDescription, privacy: .public)"
                )
            return []
        }
    }()

    /// The techniques in the export at `url`, in presentation order.
    ///
    /// Takes a path as well as serving `bundled` above, because `OndDiagrams`
    /// redraws the marketing site from the committed file itself rather than
    /// from a copy SwiftPM staged — the site and the app must be drawn from one
    /// artefact, and reading it by path is what makes that visible.
    public static func techniques(at url: URL) throws -> [Technique] {
        let export = try JSONDecoder().decode(Export.self, from: Data(contentsOf: url))
        return try export.techniques.map(Technique.init(exported:))
    }

    /// What the export can be wrong about, as opposed to what `JSONDecoder`
    /// already catches.
    public enum Failure: Error, CustomStringConvertible {
        case unknownGoal(String)
        case unknownPhaseKind(String)
        case unknownPassage(String)
        case breathWithoutPassage(String)

        public var description: String {
            switch self {
            case let .unknownGoal(value):
                "`\(value)` is not a goal this app knows"
            case let .unknownPhaseKind(value):
                "`\(value)` is not a phase kind this app knows"
            case let .unknownPassage(value):
                "`\(value)` is not a passage this app knows"
            case let .breathWithoutPassage(kind):
                "a \(kind) phase in the export names no passage"
            }
        }
    }

    fileprivate struct Export: Decodable {
        let techniques: [ExportedTechnique]
    }

    fileprivate struct ExportedTechnique: Decodable {
        let slug: String
        let name: String
        let summary: String
        let mechanism: String
        let evidence: String
        let safetyNote: String
        let goal: String
        let stages: [ExportedStage]
        let recommendedRounds: Int
        let requiresSubscription: Bool
    }

    fileprivate struct ExportedStage: Decodable {
        let phases: [ExportedPhase]
        let cycles: Int
        let openEnded: Bool
    }

    fileprivate struct ExportedPhase: Decodable {
        let kind: String
        /// Absent exactly for a hold, matching the column's `CHECK`.
        let passage: String?
        let durationMs: Int
        let minDurationMs: Int
        let maxDurationMs: Int
    }
}

private extension Technique {
    init(exported: CatalogueExport.ExportedTechnique) throws {
        try self.init(
            id: exported.slug,
            slug: exported.slug,
            name: exported.name,
            summary: exported.summary,
            goal: TechniqueGoal(exported: exported.goal),
            stages: exported.stages.map(Stage.init(exported:)),
            recommendedRounds: exported.recommendedRounds,
            mechanism: exported.mechanism,
            evidence: exported.evidence,
            safetyNote: exported.safetyNote,
            requires: exported.requiresSubscription ? .catalogue : .free
        )
    }
}

private extension Stage {
    init(exported: CatalogueExport.ExportedStage) throws {
        try self.init(
            phases: exported.phases.map(Phase.init(exported:)),
            cycles: exported.cycles,
            openEnded: exported.openEnded
        )
    }
}

private extension Phase {
    /// Unlike the app's own decoder, a missing passage on a breath is a failure
    /// rather than a fallback to the nose. This reads a committed artefact
    /// regenerated from the seed in the same `mise run generate`, so the two
    /// cannot legitimately disagree — and the figures this feeds are the only
    /// thing that would show it if they did.
    init(exported: CatalogueExport.ExportedPhase) throws {
        let kind = try PhaseKind(exported: exported.kind)
        let passage = try exported.passage.map(Passage.init(exported:))

        guard let breath = Breath(kind: kind, through: passage) else {
            throw CatalogueExport.Failure.breathWithoutPassage(exported.kind)
        }

        self.init(
            breath,
            duration: .milliseconds(exported.durationMs),
            range: .milliseconds(exported.minDurationMs) ... .milliseconds(exported.maxDurationMs)
        )
    }
}

private extension Breath {
    /// The breath a kind and an optional passage describe, or nil where a moving
    /// breath named none.
    init?(kind: PhaseKind, through passage: Passage?) {
        switch (kind, passage) {
        case let (.inhale, .some(passage)): self = .inhale(through: passage)
        case let (.exhale, .some(passage)): self = .exhale(through: passage)
        case (.holdIn, _): self = .holdIn
        case (.holdOut, _): self = .holdOut
        case (.inhale, .none), (.exhale, .none): return nil
        }
    }
}

private extension Passage {
    init(exported: String) throws {
        switch exported {
        case "NOSE": self = .nose
        case "MOUTH": self = .mouth
        case "LEFT_NOSTRIL": self = .leftNostril
        case "RIGHT_NOSTRIL": self = .rightNostril
        default: throw CatalogueExport.Failure.unknownPassage(exported)
        }
    }
}

private extension TechniqueGoal {
    /// The export speaks the contract's vocabulary — the Postgres enum's labels
    /// — which is deliberately not this type's raw value.
    init(exported: String) throws {
        switch exported {
        case "CALM": self = .calm
        case "SLEEP": self = .sleep
        case "ENERGY": self = .energy
        case "RESET": self = .reset
        case "FOCUS": self = .focus
        default: throw CatalogueExport.Failure.unknownGoal(exported)
        }
    }
}

private extension PhaseKind {
    init(exported: String) throws {
        switch exported {
        case "INHALE": self = .inhale
        case "HOLD_IN": self = .holdIn
        case "EXHALE": self = .exhale
        case "HOLD_OUT": self = .holdOut
        default: throw CatalogueExport.Failure.unknownPhaseKind(exported)
        }
    }
}
