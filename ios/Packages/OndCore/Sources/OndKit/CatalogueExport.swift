import Foundation
import os

/// The committed `catalogue.json` — the seeded reference data, exported from
/// `crates/migrate` by `mise run generate:catalogue`. Crosses the Rust/Swift
/// boundary once, into an artefact `mise run check:generated` pins. A second
/// decoding path beside the contract's `Codable` round-trip, deliberately:
/// `bundled` is what a device that has never reached the server breathes.
public enum CatalogueExport {
    private static let logger = Logger(category: "catalogue-export")

    /// The reference data this build shipped with — the seed
    /// `CachedReferenceRepository` falls back to when no fetch has ever
    /// succeeded. All three kinds together: an app that listed every exercise
    /// offline but showed an empty Moments tab looked broken in a way no
    /// explanation on the screen could fix.
    public struct Bundled: Sendable {
        public let techniques: [Technique]
        public let foundations: [FoundationTopic]
        public let occasions: OccasionCatalogue
        /// The over-breathing threshold as the seed exported it. Here so one
        /// test can compare it against `Physiology`'s compiled-in constant;
        /// nothing reads it at runtime — a downloaded threshold would put a
        /// failed fetch between somebody and a hint line.
        public let exportedFastBreathingCycle: Duration

        /// Defaults the threshold, which keeps every hand-built `Bundled` in a
        /// test to the lines it already had — the same reason `Technique.init`
        /// defaults its curated copy. Defaulting to this build's own constant
        /// also makes a hand-built value useless as evidence that anything was
        /// read, which is why the drift test reads `bundled` instead.
        public init(
            techniques: [Technique],
            foundations: [FoundationTopic],
            occasions: OccasionCatalogue,
            exportedFastBreathingCycle: Duration = Physiology.fastBreathingCycle
        ) {
            self.techniques = techniques
            self.foundations = foundations
            self.occasions = occasions
            self.exportedFastBreathingCycle = exportedFastBreathingCycle
        }

        /// What a build whose resource is missing or unreadable degrades to,
        /// and what a test about the no-seed-at-all path passes. The threshold
        /// falls back to this build's own constant, so `.empty` is no witness
        /// that the export was read — the drift test runs against `bundled`.
        public static let empty = Self(techniques: [], foundations: [], occasions: .none)
    }

    /// The seed this build shipped with, decoded once. `.empty` rather than
    /// fatal where the resource is missing or unreadable: a failure here means
    /// the build is broken, and a broken build should not be a launch crash
    /// when the honest degradation is the behaviour that predates the seed. A
    /// test is what holds the resource to its contents.
    public static let bundled: Bundled = {
        guard let url = Bundle.module.url(forResource: "catalogue", withExtension: "json") else {
            logger.error("no catalogue.json in the bundle — this build ships no seed")
            return .empty
        }

        do {
            return try reference(at: url)
        } catch {
            logger
                .error(
                    "the bundled catalogue could not be read: \(error.localizedDescription, privacy: .public)"
                )
            return .empty
        }
    }()

    /// The whole export at `url`, each list in presentation order. The routing
    /// layer is decoded separately from the techniques, and its failure does
    /// not take them with it: without techniques there is nothing to breathe,
    /// while no occasions is a state every reader already draws — one
    /// all-or-nothing decode would cost the older half for the newer's mistake.
    public static func reference(at url: URL) throws -> Bundled {
        let export = try decoded(at: url)
        let techniques = try export.techniques.map(Technique.init(exported:))

        do {
            return try Bundled(
                techniques: techniques,
                foundations: export.foundations.map(FoundationTopic.init(exported:)),
                occasions: OccasionCatalogue(
                    occasions: export.occasions.map(Occasion.init(exported:)),
                    progression: export.progression.map(ProgressionStep.init(exported:))
                ),
                exportedFastBreathingCycle: .milliseconds(export.physiology.fastBreathingCycleMs)
            )
        } catch {
            logger
                .error(
                    "the bundled routing layer could not be read, keeping the techniques: \(error.localizedDescription, privacy: .public)"
                )
            return Bundled(techniques: techniques, foundations: [], occasions: .none)
        }
    }

    /// The techniques in the export at `url`, in presentation order. Takes a
    /// path because `OndDiagrams` redraws the marketing site from the
    /// committed file itself — the site and the app must draw one artefact.
    public static func techniques(at url: URL) throws -> [Technique] {
        try decoded(at: url).techniques.map(Technique.init(exported:))
    }

    private static func decoded(at url: URL) throws -> Export {
        try JSONDecoder().decode(Export.self, from: Data(contentsOf: url))
    }

    /// What the export can be wrong about, as opposed to what `JSONDecoder`
    /// already catches.
    public enum Failure: Error, CustomStringConvertible {
        case unknownGoal(String)
        case unknownPhaseKind(String)
        case unknownPassage(String)
        case unknownManner(String)
        case unknownSurface(String)
        case unknownRegister(String)
        case unknownEvidenceGrade(String)
        case breathWithoutPassage(String)
        /// Both name the occasion's slug rather than the offending number: the
        /// number is always zero or negative, and which moment is broken is the
        /// part a reader cannot work out from the message.
        case occasionAsksForNoTime(String)
        case emptyProtocolPhase(String)

        public var description: String {
            switch self {
            case let .unknownGoal(value):
                "`\(value)` is not a goal this app knows"
            case let .unknownPhaseKind(value):
                "`\(value)` is not a phase kind this app knows"
            case let .unknownPassage(value):
                "`\(value)` is not a passage this app knows"
            case let .unknownManner(value):
                "`\(value)` is not a manner this app knows"
            case let .unknownSurface(value):
                "`\(value)` is not a delivery surface this app knows"
            case let .occasionAsksForNoTime(slug):
                "occasion `\(slug)` asks for no time at all"
            case let .emptyProtocolPhase(slug):
                "occasion `\(slug)` carries a zero-length protocol phase"
            case let .unknownRegister(value):
                "`\(value)` is not a copy register this app knows"
            case let .unknownEvidenceGrade(value):
                "`\(value)` is not an evidence grade this app knows"
            case let .breathWithoutPassage(kind):
                "a \(kind) phase in the export names no passage"
            }
        }
    }

    fileprivate struct Export: Decodable {
        let techniques: [ExportedTechnique]
        let foundations: [ExportedFoundation]
        let occasions: [ExportedOccasion]
        let progression: [ExportedProgressionStep]
        let physiology: ExportedPhysiology
    }

    fileprivate struct ExportedPhysiology: Decodable {
        let fastBreathingCycleMs: Int
    }

    fileprivate struct ExportedTechnique: Decodable {
        let slug: String
        let name: String
        let summary: String
        let mechanism: String
        let mechanismContent: ReadingContent?
        let evidence: String
        let evidenceContent: ReadingContent?
        /// Absent for nothing in the shipped export — every curated technique is
        /// graded — but optional all the same, because the field is nullable in
        /// the column it comes from and a decoder that could not read a null
        /// would fail on the first ungraded exercise this seed ever carries.
        let evidenceGrade: String?
        let safetyNote: String
        let preparation: String
        let preparationContent: ReadingContent?
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
        /// Absent for most phases, which is the opposite of `passage` above: a
        /// manner is the exception the catalogue makes, so nothing is wrong with
        /// a breath that names none.
        let manner: String?
        let durationMs: Int
        let minDurationMs: Int
        let maxDurationMs: Int
    }

    fileprivate struct ExportedFoundation: Decodable {
        let slug: String
        let question: String
        let answer: String
        let answerContent: ReadingContent?
    }

    /// Flat, as the seed is: the prescription's fields sit beside the copy
    /// rather than nested, and the Swift side rebuilds the nesting the wire
    /// carries.
    fileprivate struct ExportedOccasion: Decodable {
        let slug: String
        let name: String
        let summary: String
        let techniqueSlug: String
        let goal: String
        let surface: String
        let register: String
        let phaseDurationsMs: [Int]
        /// Empty rather than absent, matching the column — `Prescription`'s
        /// init is what turns that into nil.
        let safetyNote: String
        let durationMs: Int
    }

    fileprivate struct ExportedProgressionStep: Decodable {
        let techniqueSlug: String
        let note: String
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
            mechanismContent: exported.mechanismContent,
            evidence: exported.evidence,
            evidenceContent: exported.evidenceContent,
            evidenceGrade: exported.evidenceGrade.map(EvidenceGrade.init(exported:)),
            safetyNote: exported.safetyNote,
            preparation: exported.preparation,
            preparationContent: exported.preparationContent,
            requires: exported.requiresSubscription ? .catalogue : .free
        )
    }
}

private extension FoundationTopic {
    /// Total, like the wire's decoder: every field is a string this app only
    /// ever displays, so there is no value here it could fail to represent.
    init(exported: CatalogueExport.ExportedFoundation) {
        self.init(
            slug: exported.slug,
            question: exported.question,
            answer: exported.answer,
            answerContent: exported.answerContent
        )
    }
}

private extension Occasion {
    init(exported: CatalogueExport.ExportedOccasion) throws {
        try self.init(
            slug: exported.slug,
            name: exported.name,
            summary: exported.summary,
            prescription: Prescription(exported: exported)
        )
    }
}

private extension Prescription {
    /// Refuses what the wire's decoder refuses: an occasion decoded wrongly
    /// here is a promise made by a build that has never spoken to the server,
    /// so nothing later can correct it. The two length guards are restated,
    /// not belt-and-braces — nothing on the seed side asserts an occasion asks
    /// for time at all, so a zero would decode cleanly here while gRPC refused.
    init(exported: CatalogueExport.ExportedOccasion) throws {
        guard exported.durationMs > 0 else {
            throw CatalogueExport.Failure.occasionAsksForNoTime(exported.slug)
        }

        guard exported.phaseDurationsMs.allSatisfy({ $0 > 0 }) else {
            throw CatalogueExport.Failure.emptyProtocolPhase(exported.slug)
        }

        try self.init(
            techniqueSlug: exported.techniqueSlug,
            goal: TechniqueGoal(exported: exported.goal),
            surface: DeliverySurface(exported: exported.surface),
            register: CopyRegister(exported: exported.register),
            duration: .milliseconds(exported.durationMs),
            phaseDurations: exported.phaseDurationsMs.map(Duration.milliseconds),
            safetyNote: exported.safetyNote
        )
    }
}

private extension ProgressionStep {
    init(exported: CatalogueExport.ExportedProgressionStep) {
        self.init(techniqueSlug: exported.techniqueSlug, note: exported.note)
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
    /// A missing passage on a breath fails here as it does on the wire —
    /// nothing downstream can tell an invented passage from a restored one —
    /// and this path reads a committed artefact regenerated by the same
    /// `mise run generate`, so the two cannot legitimately disagree.
    init(exported: CatalogueExport.ExportedPhase) throws {
        let kind = try PhaseKind(exported: exported.kind)
        let passage = try exported.passage.map(Passage.init(exported:))

        guard let breath = Breath(kind: kind, through: passage) else {
            throw CatalogueExport.Failure.breathWithoutPassage(exported.kind)
        }

        try self.init(
            breath,
            duration: .milliseconds(exported.durationMs),
            range: .milliseconds(exported.minDurationMs) ... .milliseconds(exported.maxDurationMs),
            manner: exported.manner.map(Manner.init(exported:))
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
