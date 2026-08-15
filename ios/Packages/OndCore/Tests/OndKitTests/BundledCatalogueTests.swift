import Foundation
@testable import OndKit
import Testing

/// The promise a breathing app makes to a device that has never had a network:
/// it can still name an exercise, say what the exercise is for, and route
/// somebody to one from the moment they are in.
///
/// Two halves, and both are needed. The resource has to actually decode — the
/// app swallows a failure there rather than crashing, so nothing at runtime
/// would say so — and the repository has to prefer it to nothing while still
/// preferring the server to it.
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
        let techniques = CatalogueExport.bundled.techniques

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
        #expect(CatalogueExport.bundled.techniques.allSatisfy { $0.evidence != nil })
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

    @Test("The bundled export decodes into foundations with answers")
    func bundledFoundationsDecode() {
        let foundations = CatalogueExport.bundled.foundations

        #expect(!foundations.isEmpty)
        #expect(foundations.allSatisfy { !$0.answer.isEmpty && !$0.question.isEmpty })
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
