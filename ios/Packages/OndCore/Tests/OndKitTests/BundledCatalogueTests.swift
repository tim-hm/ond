import Foundation
@testable import OndKit
import Testing

/// The promise to a device that has never had a network: it can still name an
/// exercise, say what it is for, and route somebody to one. Two halves, both
/// needed: the resource has to actually decode — the app swallows a failure
/// there rather than crashing, so nothing at runtime would say so — and the
/// repository must prefer it to nothing while preferring the server to it.
@Suite("The reference data a build ships with")
struct BundledCatalogueTests {
    private struct UnreachableReader: ReferenceFetching {
        func listTechniques() async throws -> [Technique] {
            throw TechniqueRepositoryError.transport(.stub("connection refused"))
        }

        func listFoundations() async throws -> [FoundationTopic] {
            throw TechniqueRepositoryError.transport(.stub("connection refused"))
        }

        func listOccasions() async throws -> OccasionCatalogue {
            throw TechniqueRepositoryError.transport(.stub("connection refused"))
        }
    }

    private struct AnsweringReader: ReferenceFetching {
        let techniques: [Technique]

        func listTechniques() async throws -> [Technique] {
            techniques
        }

        func listFoundations() async throws -> [FoundationTopic] {
            []
        }

        func listOccasions() async throws -> OccasionCatalogue {
            .none
        }
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "bundled-catalogue-tests.\(UUID().uuidString)")
    }

    /// The one assertion nothing else makes. `CatalogueExport.bundled` answers
    /// with `.empty` when the resource is missing or malformed, and every other
    /// suite reads it by iterating — which passes vacuously over nothing at
    /// all.
    @Test("The bundled export decodes into a catalogue with breathable stages")
    func bundledCatalogueDecodes() {
        let techniques = CatalogueExport.bundled.techniques

        #expect(techniques.count >= 9)
        #expect(techniques.allSatisfy { !$0.stages.isEmpty })
        #expect(techniques.contains { $0.slug == "box-breathing" })
    }

    /// Structured mechanism copy crosses the seed, export, and decoder while
    /// retaining a complete legacy string for older clients.
    @Test("Every mechanism keeps its structure and its plain-text fallback")
    func theMechanismReachesTheScreen() throws {
        let techniques = CatalogueExport.bundled.techniques

        let box = try #require(techniques.first { $0.slug == "box-breathing" })
        let content = try #require(box.mechanismContent)
        let mechanism = try #require(box.mechanism)
        #expect(content.isWellFormed)
        #expect(content.items.count <= 3)
        #expect(mechanism == content.plainText)

        #expect(techniques.allSatisfy { technique in
            guard let content = technique.mechanismContent else { return false }
            return content.isWellFormed && technique.mechanism == content.plainText
        })
    }

    /// Evidence always presents a verdict followed by the findings, relevance,
    /// and limitations that qualify it.
    @Test("Every seeded exercise has two or three evidence bullets")
    func theEvidenceReachesTheScreen() {
        #expect(CatalogueExport.bundled.techniques.allSatisfy { technique in
            guard let content = technique.evidenceContent else { return false }
            return content.isWellFormed
                && content.listStyle == .bullets
                && (2 ... 3).contains(content.items.count)
                && technique.evidence == content.plainText
        })
    }

    /// The grade beside it, which is the half a row shows. Both directions: a
    /// decoder that dropped the field leaves every exercise ungraded, which
    /// nothing else here would notice; a catalogue graded all one way is a badge
    /// rather than a scale, which the seed asserts from its own side.
    @Test("Every seeded exercise arrives graded, and not all the same grade")
    func theEvidenceGradeReachesTheScreen() {
        let grades = CatalogueExport.bundled.techniques.map(\.evidenceGrade)

        #expect(grades.allSatisfy { $0 != nil })
        #expect(Set(grades.compactMap(\.self)).count == EvidenceGrade.allCases.count)
    }

    /// The shape survives seed, export and decode — the three hops where it can go
    /// missing without anything looking broken. On `theEvidenceReachesTheScreen`'s
    /// terms: a decoder that dropped the field leaves a cooling breath that reads
    /// exactly like a technique nobody shaped, which is the state before this existed
    /// and the one nothing else here would notice.
    @Test("The shaped breaths arrive shaped, and every manner is seeded somewhere")
    func theShapedBreathsSurviveTheExport() {
        let shaped = CatalogueExport.bundled.techniques
            .flatMap { technique in
                technique.stages.flatMap(\.phases).compactMap { phase in
                    phase.manner.map { (technique.slug, $0) }
                }
            }

        #expect(shaped.contains { $0 == ("cooling-breath", .curledTongue) })

        // Every case the app declares is one the catalogue actually breathes.
        // A manner nothing seeds is vocabulary this app carries for nothing —
        // and the seed asserts the same rule from the other side of the export.
        for manner in Manner.allCases {
            #expect(shaped.contains { $0.1 == manner }, "`\(manner)` is declared and never seeded")
        }
    }

    /// The sentence that carries what a manner cannot — the alternative for a
    /// tongue that will not roll, and the hand nothing else states. Which
    /// techniques carry one is the seed's test; this asserts the export's
    /// pairing that makes the field load-bearing, and lets a fifth preparation
    /// be seeded without breaking a Swift test about JSON.
    @Test("A shaped exercise's preparation survives the export")
    func thePreparationSurvivesTheExport() {
        let shaped = CatalogueExport.bundled.techniques
            .filter { $0.stages.flatMap(\.phases).contains { $0.manner != nil } }

        for technique in shaped {
            #expect(
                technique.preparationContent?.isWellFormed == true
                    && technique.preparation == technique.preparationContent?.plainText,
                "\(technique.slug) shapes a breath and arrived with nothing to prepare"
            )
        }
    }

    /// The half the export did not carry until the routing layer joined it, and
    /// the half nothing else in this suite would notice the loss of: a decoder
    /// that silently produced no occasions leaves a Protocols tab that looks
    /// like a device which has simply never been online.
    @Test("The bundled export decodes into occasions that resolve against the catalogue")
    func bundledOccasionsDecode() throws {
        let bundled = CatalogueExport.bundled
        let occasions = bundled.occasions.occasions
        let slugs = Set(bundled.techniques.map(\.slug))

        #expect(!occasions.isEmpty)
        #expect(!bundled.occasions.progression.isEmpty)
        // Both halves come out of one seed, so a slug that does not resolve is
        // the export having dropped or reordered something rather than the
        // server and this build disagreeing.
        #expect(occasions.allSatisfy { slugs.contains($0.prescription.techniqueSlug) })
        #expect(bundled.occasions.progression.allSatisfy { slugs.contains($0.techniqueSlug) })

        let quiet = try #require(occasions.first { $0.prescription.surface == .discreet })
        #expect(quiet.prescription.duration > .zero)
    }

    /// The protocol-owned rhythm, which is the one field that survives the wire
    /// and the export by different routes — `phaseDurationsMs` is repeated
    /// scalars on the wire and a plain array here.
    @Test("A protocol that retimes its exercise keeps the rhythm through the export")
    func aRetimedProtocolKeepsItsRhythm() throws {
        let retimed = try #require(
            CatalogueExport.bundled.occasions.occasions
                .first { !$0.prescription.phaseDurations.isEmpty }
        )

        #expect(retimed.prescription.phaseDurations.allSatisfy { $0 > .zero })
    }

    /// The two length guards, driven through a written export — the shipped one
    /// is correct, which is why it cannot show a wrong one being refused. Nothing
    /// else holds this: the seed never asserts an occasion asks for time, so a
    /// zero would decode unchallenged while the same value over gRPC lost the
    /// response. One assertion: the occasions are refused, the techniques survive.
    @Test("A zero-length occasion costs the routing layer, never the techniques")
    func aZeroLengthOccasionIsRefused() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (field, broken) in [("durationMs", "0"), ("phaseDurationsMs", "[3000, 0]")] {
            let url = directory.appending(path: "\(field).json")
            try Self.export(overriding: field, with: broken).write(to: url)

            let degraded = try CatalogueExport.reference(at: url)

            #expect(degraded.occasions == .none, "a zero \(field) should cost the occasions")
            #expect(
                degraded.techniques.map(\.slug) == CatalogueExport.bundled.techniques.map(\.slug),
                "a zero \(field) should not cost the techniques"
            )
        }
    }

    /// The shipped export with one occasion field replaced, so the fixture stays
    /// whatever shape the generator actually writes rather than a hand-typed
    /// guess at it — the thing a literal gets wrong and a decoder never mentions.
    private static func export(overriding field: String, with value: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "catalogue", withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        let target = try #require(
            lines.lastIndex { $0.contains("\"\(field)\"") },
            "the export should carry a \(field)"
        )
        let indent = String(lines[target].prefix { $0 == " " })
        lines[target] = "\(indent)\"\(field)\": \(value),"

        return Data(lines.joined(separator: "\n").utf8)
    }

    @Test("The bundled export decodes into foundations with answers")
    func bundledFoundationsDecode() {
        let foundations = CatalogueExport.bundled.foundations

        #expect(!foundations.isEmpty)
        #expect(foundations.allSatisfy {
            !$0.answer.isEmpty
                && !$0.question.isEmpty
                && $0.answerContent.isWellFormed
                && $0.answer == $0.answerContent.plainText
        })
    }

    /// The asymmetry this bundling exists to remove. Every kind answers from the
    /// seed, so which screens work out of range no longer depends on which ones
    /// were opened in range.
    @Test("A device that has never reached the server has all three kinds")
    func servesEverySeedWithNothingCached() async {
        let repository = CachedReferenceRepository(
            caching: UnreachableReader(),
            directory: temporaryDirectory()
        )

        #expect(await repository.localFoundations() == CatalogueExport.bundled.foundations)
        #expect(await repository.localOccasions() == CatalogueExport.bundled.occasions)
    }

    /// The other half of that promise: a build whose resource could not be read
    /// degrades to the behaviour that predates the seed rather than insisting
    /// there is nothing to show.
    @Test("An unreadable seed leaves the techniques and foundations waiting, not empty")
    func anEmptySeedIsNoSeed() async {
        let repository = CachedReferenceRepository(
            caching: UnreachableReader(),
            directory: temporaryDirectory(),
            seed: .empty
        )

        #expect(await repository.localTechniques() == nil)
        #expect(await repository.localFoundations() == nil)
        // Occasions still answer, because having none of them is a state every
        // surface already draws rather than a screen with nothing to say.
        #expect(await repository.localOccasions() == .some(.none))
    }

    @Test("A device that has never reached the server still has a catalogue")
    func servesTheSeedWithNothingCached() async {
        let repository = CachedReferenceRepository(
            caching: UnreachableReader(),
            directory: temporaryDirectory()
        )

        #expect(await repository.localTechniques() == CatalogueExport.bundled.techniques)
    }

    /// The precedence the seed must not invert: once the server has answered
    /// once, its catalogue is the one being served offline, however much newer
    /// the build's seed happens to be.
    @Test("A catalogue the server sent outranks the seed")
    func prefersTheSnapshotToTheSeed() async throws {
        let directory = temporaryDirectory()
        let served = [
            Technique(
                id: "served",
                slug: "served",
                name: "Served",
                summary: "",
                goal: .calm,
                stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 4)],
                recommendedRounds: 1
            ),
        ]

        _ = try await CachedReferenceRepository(
            caching: AnsweringReader(techniques: served),
            directory: directory
        ).refreshTechniques()

        let offline = CachedReferenceRepository(
            caching: UnreachableReader(),
            directory: directory
        )

        #expect(await offline.localTechniques() == served)
    }
}
