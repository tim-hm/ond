import Foundation
@testable import OndKit
import Testing

/// The promise a breathing app makes to a device that has never had a network:
/// it can still name an exercise and breathe it.
///
/// Two halves, and both are needed. The resource has to actually decode — the
/// app swallows a failure there rather than crashing, so nothing at runtime
/// would say so — and the repository has to prefer it to nothing while still
/// preferring the server to it.
@Suite("The catalogue a build ships with")
struct BundledCatalogueTests {
    private struct UnreachableReader: TechniqueReading {
        func listTechniques() async throws -> [Technique] {
            throw TechniqueRepositoryError.transport("connection refused")
        }

        func listFoundations() async throws -> [FoundationTopic] {
            throw TechniqueRepositoryError.transport("connection refused")
        }

        func listRoutes() async throws -> Routes {
            throw TechniqueRepositoryError.transport("connection refused")
        }
    }

    private struct AnsweringReader: TechniqueReading {
        let techniques: [Technique]

        func listTechniques() async throws -> [Technique] {
            techniques
        }

        func listFoundations() async throws -> [FoundationTopic] {
            []
        }

        func listRoutes() async throws -> Routes {
            .none
        }
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "bundled-catalogue-tests.\(UUID().uuidString)")
    }

    /// The one assertion nothing else makes. `CatalogueExport.bundled` answers
    /// with an empty catalogue when the resource is missing or malformed, and
    /// every other suite reads it by iterating — which passes vacuously over
    /// nothing at all.
    @Test("The bundled export decodes into a catalogue with breathable stages")
    func bundledCatalogueDecodes() {
        let techniques = CatalogueExport.bundled

        #expect(techniques.count >= 9)
        #expect(techniques.allSatisfy { !$0.stages.isEmpty })
        #expect(techniques.contains { $0.slug == "box-breathing" })
    }

    @Test("A device that has never reached the server still has a catalogue")
    func servesTheSeedWithNothingCached() async throws {
        let repository = CachedTechniqueRepository(
            caching: UnreachableReader(),
            directory: temporaryDirectory()
        )

        #expect(try await repository.listTechniques() == CatalogueExport.bundled)
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

        _ = try await CachedTechniqueRepository(
            caching: AnsweringReader(techniques: served),
            directory: directory
        ).listTechniques()

        let offline = CachedTechniqueRepository(
            caching: UnreachableReader(),
            directory: directory
        )

        #expect(try await offline.listTechniques() == served)
    }
}
