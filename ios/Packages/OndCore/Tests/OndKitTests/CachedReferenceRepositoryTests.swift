import Foundation
@testable import OndKit
import Testing

/// What is under test is the offline promise for reference data: once any fetch
/// has succeeded, the server being unreachable costs freshness, never the
/// catalogue.
@Suite("Cached reference repository")
struct CachedReferenceRepositoryTests {
    /// Answers with whatever it was configured with, and can be told to refuse
    /// — which is what a stopped API service looks like.
    private final class ScriptedReader: ReferenceFetching, @unchecked Sendable {
        var techniques: [Technique]
        var foundations: [FoundationTopic]
        var routes: Routes
        var isReachable = true

        init(
            techniques: [Technique] = [],
            foundations: [FoundationTopic] = [],
            routes: Routes = .none
        ) {
            self.techniques = techniques
            self.foundations = foundations
            self.routes = routes
        }

        func listTechniques() async throws -> [Technique] {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return techniques
        }

        func listFoundations() async throws -> [FoundationTopic] {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return foundations
        }

        func listRoutes() async throws -> Routes {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return routes
        }
    }

    /// A directory nobody else shares, torn down by the OS rather than by a
    /// cleanup step a failing test would skip.
    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "catalogue-cache-tests.\(UUID().uuidString)")
    }

    private func technique(slug: String) -> Technique {
        Technique(
            id: slug,
            slug: slug,
            name: slug,
            summary: "",
            goal: .calm,
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(4), range: .seconds(2) ... .seconds(8)),
                ],
                cycles: 4
            )],
            recommendedRounds: 1,
            safetyNote: "seated only"
        )
    }

    @Test("A fetched catalogue survives the server becoming unreachable")
    func fallsBackToTheLastFetch() async throws {
        let directory = temporaryDirectory()
        let reader = ScriptedReader(
            techniques: [technique(slug: "box-breathing")],
            foundations: [FoundationTopic(slug: "why", question: "Why?", answer: "Because.")]
        )
        let repository = CachedReferenceRepository(caching: reader, directory: directory)

        _ = try await repository.refreshTechniques()
        _ = try await repository.refreshFoundations()
        reader.isReachable = false

        // A second repository over the same directory, because the fallback
        // that matters is a later launch reading a file an earlier one wrote —
        // not one instance remembering its own state.
        let relaunched = CachedReferenceRepository(caching: reader, directory: directory)
        let techniques = await relaunched.localTechniques()
        let foundations = await relaunched.localFoundations()

        #expect(techniques == [technique(slug: "box-breathing")])
        #expect(foundations?.map(\.slug) == ["why"])

        await #expect(throws: TechniqueRepositoryError.transport(.stub("connection refused"))) {
            _ = try await relaunched.refreshTechniques()
        }
        #expect(await relaunched.localTechniques() == techniques)
    }

    /// Foundations are the surviving case: the export carries techniques alone,
    /// so there is nothing to seed them with and the original error is still
    /// what a first-ever launch out of range sees.
    @Test("A first-ever launch with no connection and no seed sees the original error")
    func rethrowsWithNothingCached() async {
        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(caching: reader, directory: temporaryDirectory())

        #expect(await repository.localFoundations() == nil)

        await #expect(throws: TechniqueRepositoryError.transport(.stub("connection refused"))) {
            _ = try await repository.refreshFoundations()
        }
    }

    @Test("A newer fetch replaces the snapshot an older one wrote")
    func keepsTheLatestFetch() async throws {
        let directory = temporaryDirectory()
        let reader = ScriptedReader(techniques: [technique(slug: "old")])
        let repository = CachedReferenceRepository(caching: reader, directory: directory)

        _ = try await repository.refreshTechniques()
        reader.techniques = [technique(slug: "new")]
        _ = try await repository.refreshTechniques()

        let techniques = await repository.localTechniques()
        #expect(techniques?.map(\.slug) == ["new"])
    }

    @Test("An unreadable snapshot falls through to the seed")
    func survivesACorruptCacheFile() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "catalogue.json"))

        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(
            caching: reader,
            directory: directory,
            seed: [technique(slug: "box-breathing")]
        )

        #expect(await repository.localTechniques()?.map(\.slug) == ["box-breathing"])
    }

    @Test("An unreadable snapshot with no seed falls through to the fetch error")
    func survivesACorruptCacheFileWithNoSeed() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "catalogue.json"))

        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(caching: reader, directory: directory, seed: [])

        #expect(await repository.localTechniques() == nil)

        await #expect(throws: TechniqueRepositoryError.transport(.stub("connection refused"))) {
            _ = try await repository.refreshTechniques()
        }
    }

    @Test("Unreadable foundation and route snapshots use their own fallbacks")
    func corruptNonCatalogueSnapshotsUseTheirFallbacks() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "foundations.json"))
        try Data("not json".utf8).write(to: directory.appending(path: "routes.json"))

        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(caching: reader, directory: directory)

        #expect(await repository.localFoundations() == nil)
        #expect(await repository.localRoutes() == .some(.none))
    }

    @Test("Routes default to none before the first download")
    func routesHaveAnEmptyLocalDefault() async {
        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(caching: reader, directory: temporaryDirectory())

        #expect(await repository.localRoutes() == .some(.none))
    }

    @Test("A fresh foundation response replaces the complete cached set")
    func replacesFoundationsRatherThanMerging() async throws {
        let directory = temporaryDirectory()
        let reader = ScriptedReader(
            foundations: [
                FoundationTopic(slug: "kept", question: "Kept?", answer: "Yes."),
                FoundationTopic(slug: "retired", question: "Retired?", answer: "Not now."),
            ]
        )
        let repository = CachedReferenceRepository(caching: reader, directory: directory)
        _ = try await repository.refreshFoundations()

        reader.foundations = [
            FoundationTopic(slug: "kept", question: "Still kept?", answer: "Yes."),
        ]
        _ = try await repository.refreshFoundations()

        let relaunched = CachedReferenceRepository(caching: reader, directory: directory)
        #expect(await relaunched.localFoundations()?.map(\.slug) == ["kept"])
    }
}
