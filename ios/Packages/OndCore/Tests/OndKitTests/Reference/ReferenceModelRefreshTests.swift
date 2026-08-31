import Foundation
@testable import OndKit
import Testing

@MainActor
@Suite("Reference model refreshes")
struct ReferenceModelRefreshTests {
    private actor Gate<Value: Sendable> {
        private var answer: Value?
        private var waiters: [CheckedContinuation<Value, Never>] = []

        func wait() async -> Value {
            if let answer {
                return answer
            }
            return await withCheckedContinuation { waiters.append($0) }
        }

        func open(with answer: Value) {
            self.answer = answer
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume(returning: answer) }
        }
    }

    private struct Counts: Equatable, Sendable {
        let techniques: Int
        let foundations: Int
        let occasions: Int
    }

    private actor GatedReferences: TechniqueReading, FoundationReading, OccasionReading {
        let techniqueGate = Gate<[Technique]>()
        let foundationGate = Gate<[FoundationTopic]>()
        let occasionGate = Gate<OccasionCatalogue>()

        private var techniqueCount = 0
        private var foundationCount = 0
        private var occasionCount = 0
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        func localTechniques() async -> [Technique]? {
            nil
        }

        func refreshTechniques() async throws -> [Technique] {
            techniqueCount += 1
            signalIfStarted()
            return await techniqueGate.wait()
        }

        func localFoundations() async -> [FoundationTopic]? {
            nil
        }

        func refreshFoundations() async throws -> [FoundationTopic] {
            foundationCount += 1
            signalIfStarted()
            return await foundationGate.wait()
        }

        func localOccasions() async -> OccasionCatalogue? {
            .some(.none)
        }

        func refreshOccasions() async throws -> OccasionCatalogue {
            occasionCount += 1
            signalIfStarted()
            return await occasionGate.wait()
        }

        func waitUntilAllStarted() async {
            guard !allStarted else {
                return
            }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func counts() -> Counts {
            Counts(
                techniques: techniqueCount,
                foundations: foundationCount,
                occasions: occasionCount
            )
        }

        func open(
            techniques: [Technique],
            foundations: [FoundationTopic],
            occasions: OccasionCatalogue
        ) async {
            await techniqueGate.open(with: techniques)
            await foundationGate.open(with: foundations)
            await occasionGate.open(with: occasions)
        }

        private var allStarted: Bool {
            techniqueCount > 0 && foundationCount > 0 && occasionCount > 0
        }

        private func signalIfStarted() {
            guard allStarted else { return }
            let waiting = startWaiters
            startWaiters = []
            waiting.forEach { $0.resume() }
        }
    }

    private actor RetryingFoundations: FoundationReading {
        private(set) var attempts = 0
        let topics: [FoundationTopic]

        init(topics: [FoundationTopic]) {
            self.topics = topics
        }

        func localFoundations() async -> [FoundationTopic]? {
            nil
        }

        func refreshFoundations() async throws -> [FoundationTopic] {
            attempts += 1
            if attempts == 1 {
                throw TechniqueRepositoryError.transport(.stub("offline"))
            }
            return topics
        }
    }

    private struct GatedFoundations: FoundationReading {
        let local: [FoundationTopic]
        let gate: Gate<[FoundationTopic]>

        func localFoundations() async -> [FoundationTopic]? {
            local
        }

        func refreshFoundations() async throws -> [FoundationTopic] {
            await gate.wait()
        }
    }

    private func technique(slug: TechniqueSlug) -> Technique {
        Technique(
            id: TechniqueId(rawValue: slug.rawValue),
            slug: slug,
            name: slug.rawValue,
            summary: "",
            goal: .calm,
            stages: [Stage(
                phases: [Phase(kind: .inhale, duration: .seconds(4))],
                cycles: 4
            )],
            recommendedRounds: 1
        )
    }

    @Test("Concurrent callers produce one refresh for each reference kind")
    func deduplicatesEveryReferenceKind() async {
        let references = GatedReferences()
        let catalogue = TechniqueListModel(techniques: references)
        let foundations = FoundationsModel(topics: references)
        let occasions = OccasionCatalogueModel(occasions: references)

        async let catalogueFirst: Void = catalogue.refresh()
        async let catalogueSecond: Void = catalogue.refresh()
        async let foundationsFirst: Void = foundations.refresh()
        async let foundationsSecond: Void = foundations.refresh()
        async let occasionsFirst: Void = occasions.refresh()
        async let occasionsSecond: Void = occasions.refresh()

        await references.waitUntilAllStarted()
        await references.open(
            techniques: [technique(slug: "fresh")],
            foundations: [
                FoundationTopic(slug: "practice", question: "Practice?", answer: "Often."),
            ],
            occasions: .none
        )

        _ = await (
            catalogueFirst,
            catalogueSecond,
            foundationsFirst,
            foundationsSecond,
            occasionsFirst,
            occasionsSecond
        )
        #expect(await references.counts() == Counts(
            techniques: 1,
            foundations: 1,
            occasions: 1
        ))
    }

    @Test("A first foundation download can fail and then succeed on retry")
    func retriesTheFirstFoundationDownload() async {
        let fresh = [
            FoundationTopic(slug: "practice", question: "Practice?", answer: "Often."),
        ]
        let reader = RetryingFoundations(topics: fresh)
        let model = FoundationsModel(topics: reader)

        await model.loadIfNeeded()
        guard case .failed = model.state else {
            Issue.record("expected the first download to fail")
            return
        }

        await model.refresh()
        guard case let .loaded(topics) = model.state else {
            Issue.record("expected retry to load the foundations")
            return
        }
        #expect(topics == fresh)
        #expect(await reader.attempts == 2)
    }

    @Test("Fresh foundations remove retired visible topics")
    func replacesVisibleFoundations() async throws {
        let gate = Gate<[FoundationTopic]>()
        let model = FoundationsModel(
            topics: GatedFoundations(
                local: [FoundationTopic(
                    slug: "retired",
                    question: "Old?",
                    answer: "Old."
                )],
                gate: gate
            )
        )

        await model.loadIfNeeded()
        guard case let .loaded(initial) = model.state else {
            Issue.record("expected local foundations to be visible")
            return
        }
        #expect(initial.map(\.slug) == ["retired"])

        await gate.open(with: [
            FoundationTopic(slug: "current", question: "Current?", answer: "Current."),
        ])
        try await settle { loadedFoundationSlugs(in: model) == ["current"] }

        #expect(loadedFoundationSlugs(in: model) == ["current"])
    }

    private func loadedFoundationSlugs(in model: FoundationsModel) -> [String]? {
        guard case let .loaded(topics) = model.state else { return nil }
        return topics.map(\.slug)
    }
}
