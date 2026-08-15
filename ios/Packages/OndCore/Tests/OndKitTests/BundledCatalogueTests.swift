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
    private struct UnreachableReader: ReferenceFetching {
        func listTechniques() async throws -> [Technique] {
            throw TechniqueRepositoryError.transport(.stub("connection refused"))
        }

        func listFoundations() async throws -> [FoundationTopic] {
            throw TechniqueRepositoryError.transport(.stub("connection refused"))
        }

        func listRoutes() async throws -> Routes {
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

    /// The mechanism paragraph an exercise's screen opens on, all the way from
    /// `seed/catalogue.rs` through the export to a decoded `Technique`.
    ///
    /// This asserts only what the round trip can break: the blank line between
    /// box breathing's paragraphs is the one character a pass through JSON is
    /// most likely to eat, and the sweep says the export dropped nobody's
    /// paragraph. The copy itself, and the catalogue's completeness, are
    /// asserted where they are authored — the seed's own tests — so a retuned
    /// sentence never breaks a Swift test about JSON.
    @Test("The mechanism paragraph survives the seed, the export, and the decode")
    func theMechanismReachesTheScreen() throws {
        let techniques = CatalogueExport.bundled

        let box = try #require(techniques.first { $0.slug == "box-breathing" })
        let mechanism = try #require(box.mechanism)
        #expect(mechanism.contains("\n\n"))

        #expect(techniques.allSatisfy { $0.mechanism != nil })
    }

    /// The evidence footnote, on the same terms and for the same one reason: a
    /// field the export stopped carrying would leave every technique looking
    /// exactly like one that was never written about.
    ///
    /// The copy's own rule — one paragraph, where a mechanism is two — is
    /// asserted in the seed where it is authored, and stays there: a round trip
    /// through JSON can eat a blank line, which is what the mechanism test
    /// catches, but it cannot introduce one.
    @Test("Every seeded exercise says what its evidence is worth")
    func theEvidenceReachesTheScreen() {
        #expect(CatalogueExport.bundled.allSatisfy { $0.evidence != nil })
    }

    @Test("A device that has never reached the server still has a catalogue")
    func servesTheSeedWithNothingCached() async {
        let repository = CachedReferenceRepository(
            caching: UnreachableReader(),
            directory: temporaryDirectory()
        )

        #expect(await repository.localTechniques() == CatalogueExport.bundled)
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
