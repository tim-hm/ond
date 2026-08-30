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
        var occasions: OccasionCatalogue
        var isReachable = true

        init(
            techniques: [Technique] = [],
            foundations: [FoundationTopic] = [],
            occasions: OccasionCatalogue = .none
        ) {
            self.techniques = techniques
            self.foundations = foundations
            self.occasions = occasions
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

        func listOccasions() async throws -> OccasionCatalogue {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return occasions
        }
    }

    /// A directory nobody else shares, torn down by the OS rather than by a
    /// cleanup step a failing test would skip.
    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "catalogue-cache-tests.\(UUID().uuidString)")
    }

    private func technique(slug: TechniqueSlug) -> Technique {
        Technique(
            id: TechniqueId(rawValue: slug.rawValue),
            slug: slug,
            name: slug.rawValue,
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

    /// With nothing cached and nothing seeded, the fetch error is what a
    /// first-ever launch out of range sees — which is the state that shows a
    /// person a failure screen rather than a stale one.
    @Test("A first-ever launch with no connection and no seed sees the original error")
    func rethrowsWithNothingCached() async {
        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(
            caching: reader,
            directory: temporaryDirectory(),
            seed: .empty
        )

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
            seed: .init(
                techniques: [technique(slug: "box-breathing")],
                foundations: [],
                occasions: .none
            )
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
        let repository = CachedReferenceRepository(
            caching: reader,
            directory: directory,
            seed: .empty
        )

        #expect(await repository.localTechniques() == nil)

        await #expect(throws: TechniqueRepositoryError.transport(.stub("connection refused"))) {
            _ = try await repository.refreshTechniques()
        }
    }

    /// A corrupt snapshot falls through to the seed on every kind, not just the
    /// techniques. Written with a bare seed so the assertion is about the fall
    /// through rather than about what this build happens to ship.
    @Test("Unreadable foundation and occasion snapshots fall through to the seed")
    func corruptNonCatalogueSnapshotsUseTheirFallbacks() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "foundations.json"))
        try Data("not json".utf8).write(to: directory.appending(path: "occasions.json"))

        let reader = ScriptedReader()
        reader.isReachable = false
        let seeded = OccasionCatalogue(progression: [
            ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ])
        let repository = CachedReferenceRepository(
            caching: reader,
            directory: directory,
            seed: .init(
                techniques: [],
                foundations: [FoundationTopic(slug: "why", question: "Why?", answer: "Because.")],
                occasions: seeded
            )
        )

        #expect(await repository.localFoundations()?.map(\.slug) == ["why"])
        #expect(await repository.localOccasions() == seeded)
    }

    /// Occasions answer even with nothing seeded, unlike the two kinds above:
    /// having none of them is a state every surface already draws.
    @Test("Occasions default to none before the first download")
    func occasionsHaveAnEmptyLocalDefault() async {
        let reader = ScriptedReader()
        reader.isReachable = false
        let repository = CachedReferenceRepository(
            caching: reader,
            directory: temporaryDirectory(),
            seed: .empty
        )

        #expect(await repository.localOccasions() == .some(.none))
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
