import Foundation
@testable import OndKit
import Testing

/// Pins the stale-while-revalidate hand-off from a disk snapshot to a response
/// that remains held until the test explicitly releases it.
@MainActor
@Suite("Refreshing reference data after local display")
struct ReferenceRefreshTests {
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

    private actor Counter {
        private(set) var count = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func bump() {
            count += 1
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }

        func waitForFirst() async {
            guard count < 1 else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private struct GatedReader: ReferenceFetching {
        let techniques: Gate<[Technique]>
        let counter: Counter

        func listTechniques() async throws -> [Technique] {
            await counter.bump()
            return await techniques.wait()
        }

        func listFoundations() async throws -> [FoundationTopic] {
            []
        }

        func listOccasions() async throws -> OccasionCatalogue {
            .none
        }
    }

    private func technique(slug: TechniqueSlug) -> Technique {
        Technique(
            id: TechniqueId(rawValue: slug.rawValue),
            slug: slug,
            name: slug.rawValue,
            summary: "",
            goal: .calm,
            stages: [
                Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 4),
            ],
            recommendedRounds: 1
        )
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "reference-refresh-tests.\(UUID().uuidString)")
    }

    @Test("A held response replaces local, visible, and persisted data when it arrives")
    func aLateResponseStillReplacesEveryCopy() async throws {
        let directory = temporaryDirectory()
        let old = [technique(slug: "old")]
        let fresh = [technique(slug: "fresh")]
        let seeded = CachedReferenceRepository(
            caching: AnsweringReader(techniques: old),
            directory: directory
        )
        _ = try await seeded.refreshTechniques()

        let gate = Gate<[Technique]>()
        let counter = Counter()
        let repository = CachedReferenceRepository(
            caching: GatedReader(techniques: gate, counter: counter),
            directory: directory,
            seed: .empty
        )
        let model = TechniqueListModel(techniques: repository)

        await model.loadIfNeeded()

        guard case let .loaded(initial) = model.state else {
            Issue.record("expected the cached catalogue to be visible")
            return
        }
        #expect(initial == old)

        // Reminders and notification routing both call `loadIfNeeded` before
        // resolving a slug. The held request must not put that local lookup
        // back behind the network.
        #expect(
            await model.reminderTechnique(forFirstOf: [.calm])?.slug == "old"
        )
        await counter.waitForFirst()

        await gate.open(with: fresh)
        try await settle { loadedSlugs(in: model) == ["fresh"] }

        #expect(loadedSlugs(in: model) == ["fresh"])
        #expect(await counter.count == 1)
        #expect(await repository.localTechniques()?.map(\.slug) == ["fresh"])

        let relaunched = CachedReferenceRepository(
            caching: AnsweringReader(techniques: []),
            directory: directory,
            seed: .empty
        )
        #expect(await relaunched.localTechniques()?.map(\.slug) == ["fresh"])
    }

    @Test("Cancelling the view task does not cancel the model refresh")
    func refreshSurvivesCallerCancellation() async {
        let gate = Gate<[Technique]>()
        let counter = Counter()
        let repository = CachedReferenceRepository(
            caching: GatedReader(techniques: gate, counter: counter),
            directory: temporaryDirectory(),
            seed: .empty
        )
        let model = TechniqueListModel(techniques: repository)
        let viewTask = Task { await model.refresh() }

        await counter.waitForFirst()
        viewTask.cancel()
        await gate.open(with: [technique(slug: "late")])
        await viewTask.value

        #expect(loadedSlugs(in: model) == ["late"])
        #expect(await counter.count == 1)
    }

    private func loadedSlugs(in model: TechniqueListModel) -> [TechniqueSlug]? {
        guard case let .loaded(techniques) = model.state else { return nil }
        return techniques.map(\.slug)
    }
}
