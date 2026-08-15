import Foundation
import os

/// The committed `catalogue.json` — the seeded reference data, exported from
/// `crates/migrate` by `mise run generate:catalogue`.
///
/// The catalogue lives in Rust and the geometry that draws it lives here, so
/// something has to cross between the two languages. This crosses it once, into
/// an artefact `mise run check:generated` pins the export of, rather than once
/// per consumer.
///
/// A second decoding path onto the domain types, alongside the contract's: the
/// app fetches this data over gRPC and caches it, and the `Codable`
/// conformances round-trip *that*, while this reads the Rust seed's field
/// names. Both ship, deliberately — `bundled` below is what a device that has
/// never reached the server breathes.
public enum CatalogueExport {
    private static let logger = Logger(category: "catalogue-export")

    /// The reference data this build shipped with — the seed
    /// `CachedReferenceRepository` falls back to when no fetch has ever
    /// succeeded.
    ///
    /// All three together rather than the techniques alone, because a person
    /// cannot tell which screens were downloaded and which were compiled in. An
    /// app that listed every exercise offline but showed an empty Protocols tab
    /// looked broken in a way no explanation on the screen could fix.
    public struct Bundled: Sendable {
        public let techniques: [Technique]
        public let foundations: [FoundationTopic]
        public let occasions: OccasionCatalogue
        /// The facts about a body the seed exported alongside the copy.
        ///
        /// Carried so a test can compare them against `Physiology`'s compiled-in
        /// constants, which is the whole reason the seed exports them. Nothing
        /// in the app reads this at runtime — a threshold that arrived with a
        /// download would put a failed fetch between somebody and a hint line.
        public let physiology: Physiology.Exported

        /// Defaults the physiology, which keeps every hand-built `Bundled` in a
        /// test to the lines it already had — the same reason `Technique.init`
        /// defaults its curated copy. Only the one drift test has a reason to
        /// pass anything else, and it reads `bundled` rather than building one.
        public init(
            techniques: [Technique],
            foundations: [FoundationTopic],
            occasions: OccasionCatalogue,
            physiology: Physiology.Exported = .compiledIn
        ) {
            self.techniques = techniques
            self.foundations = foundations
            self.occasions = occasions
            self.physiology = physiology
        }

        /// What a build whose resource is missing or unreadable degrades to,
        /// and what a test that is about the no-seed-at-all path passes.
        ///
        /// The physiology falls back to the compiled-in constants rather than to
        /// nothing. That makes `.empty` agree with itself but *not* a witness
        /// that the export was read — which is why the test asserting the two
        /// agree runs against `bundled` and would pass vacuously here.
        public static let empty = Self(techniques: [], foundations: [], occasions: .none)
    }

    /// The seed this build shipped with, decoded once.
    ///
    /// `.empty` rather than fatal where the resource is missing or unreadable.
    /// It is a committed artefact pinned by `mise run check:generated` and
    /// decoded by a decoder written for exactly it, so a failure here means the
    /// build is broken — and a broken build should not be a launch crash for
    /// everybody when the honest degradation is the behaviour that predates
    /// this seed. What actually holds the resource to its contents is a test,
    /// which costs nothing to fail and reaches nobody's launch screen.
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

    /// The whole export at `url`, each list in presentation order.
    public static func reference(at url: URL) throws -> Bundled {
        let export = try decoded(at: url)

        return try Bundled(
            techniques: export.techniques.map(Technique.init(exported:)),
            foundations: export.foundations.map(FoundationTopic.init(exported:)),
            occasions: OccasionCatalogue(
                occasions: export.occasions.map(Occasion.init(exported:)),
                progression: export.progression.map(ProgressionStep.init(exported:))
            ),
            physiology: Physiology.Exported(
                fastBreathingCycle: .milliseconds(export.physiology.fastBreathingCycleMs)
            )
        )
    }

    /// The techniques in the export at `url`, in presentation order.
    ///
    /// Takes a path as well as serving `bundled` above, because `OndDiagrams`
    /// redraws the marketing site from the committed file itself rather than
    /// from a copy SwiftPM staged — the site and the app must be drawn from one
    /// artefact, and reading it by path is what makes that visible.
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
        case breathWithoutPassage(String)

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
            case let .unknownRegister(value):
                "`\(value)` is not a copy register this app knows"
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
        let evidence: String
        let safetyNote: String
        let preparation: String
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
        /// Absent for all but three phases, which is the opposite of `passage`
        /// above: a manner is the exception the catalogue makes, so nothing is
        /// wrong with a breath that names none.
        let manner: String?
        let durationMs: Int
        let minDurationMs: Int
        let maxDurationMs: Int
    }

    fileprivate struct ExportedFoundation: Decodable {
        let slug: String
        let question: String
        let answer: String
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
            evidence: exported.evidence,
            safetyNote: exported.safetyNote,
            preparation: exported.preparation,
            requires: exported.requiresSubscription ? .catalogue : .free
        )
    }
}

private extension FoundationTopic {
    /// Total, like the wire's decoder: every field is a string this app only
    /// ever displays, so there is no value here it could fail to represent.
    init(exported: CatalogueExport.ExportedFoundation) {
        self.init(slug: exported.slug, question: exported.question, answer: exported.answer)
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
    /// Refuses what the wire's decoder refuses, for a reason this path has to
    /// itself: an occasion decoded wrongly here is a promise about a session
    /// made by a build that has never spoken to the server, so nothing later
    /// can correct it. The seed's own tests hold the same invariants on the
    /// other side of the export, and this is the second lock on the same door.
    init(exported: CatalogueExport.ExportedOccasion) throws {
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
    /// A missing passage on a breath is a failure here for the reason it is one
    /// on the wire — nothing downstream can tell an invented passage from a
    /// restored one — and for a second reason this path has to itself. It reads
    /// a committed artefact regenerated from the seed in the same
    /// `mise run generate`, so the two cannot legitimately disagree, and the
    /// figures this feeds are the only thing that would show it if they did.
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
