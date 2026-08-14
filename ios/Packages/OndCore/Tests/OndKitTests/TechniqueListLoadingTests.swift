import Foundation
@testable import OndKit
import Testing

/// Drives the real `TechniqueListModel` state machine through the
/// `TechniqueReading` seam — the protocol exists so this suite needs no server.
@MainActor
@Suite("Loading the technique catalogue")
struct TechniqueListLoadingTests {
    private struct StubReader: TechniqueReading {
        let local: [Technique]?
        let result: Result<[Technique], TechniqueRepositoryError>

        init(
            local: [Technique]? = nil,
            result: Result<[Technique], TechniqueRepositoryError>
        ) {
            self.local = local
            self.result = result
        }

        func localTechniques() async -> [Technique]? {
            local
        }

        func refreshTechniques() async throws -> [Technique] {
            try result.get()
        }
    }

    private actor Counter {
        private(set) var count = 0
        private var firstWaiters: [CheckedContinuation<Void, Never>] = []

        func bump() {
            count += 1
            let waiters = firstWaiters
            firstWaiters = []
            waiters.forEach { $0.resume() }
        }

        func waitForFirst() async {
            guard count < 1 else { return }
            await withCheckedContinuation { firstWaiters.append($0) }
        }
    }

    private struct CountingReader: TechniqueReading {
        let counter: Counter
        let local: [Technique]?
        let techniques: [Technique]

        func localTechniques() async -> [Technique]? {
            local
        }

        func refreshTechniques() async throws -> [Technique] {
            await counter.bump()
            return techniques
        }
    }

    private func technique(slug: String) -> Technique {
        Technique(
            id: slug,
            slug: slug,
            name: slug,
            summary: "",
            goal: .calm,
            stages: [
                Stage(phases: [Phase(kind: .inhale, duration: .milliseconds(4000))], cycles: 8),
            ],
            recommendedRounds: 1
        )
    }

    @Test("A successful load lands in .loaded with order preserved")
    func loadsTechniques() async {
        let model = TechniqueListModel(
            techniques: StubReader(result: .success([technique(slug: "a"), technique(slug: "b")]))
        )

        await model.refresh()

        guard case let .loaded(techniques) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(techniques.map(\Technique.slug) == ["a", "b"])
    }

    /// The model is shared by every tab root. Once local data is visible, those
    /// roots must not each start another foreground request.
    @Test("Repeated loadIfNeeded calls start one background refresh")
    func sharesOneInitialRefresh() async {
        let counter = Counter()
        let model = TechniqueListModel(
            techniques: CountingReader(
                counter: counter,
                local: [technique(slug: "old")],
                techniques: [technique(slug: "new")]
            )
        )

        async let first: Void = model.loadIfNeeded()
        async let second: Void = model.loadIfNeeded()
        _ = await (first, second)
        await model.loadIfNeeded()
        await counter.waitForFirst()

        #expect(await counter.count == 1)
        guard case .loaded = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
    }

    @Test("An explicit refresh still refetches after the initial one")
    func explicitRefreshRefetches() async {
        let counter = Counter()
        let model = TechniqueListModel(
            techniques: CountingReader(
                counter: counter,
                local: nil,
                techniques: [technique(slug: "a")]
            )
        )

        await model.refresh()
        await model.refresh()

        #expect(await counter.count == 2)
    }

    /// The failure has to stay distinguishable from an empty catalogue — a list
    /// view that renders "no techniques" when the server is unreachable is the
    /// bug this guards.
    @Test("A transport failure lands in .failed, not an empty .loaded")
    func propagatesTransportFailure() async {
        let model = TechniqueListModel(
            techniques: StubReader(result: .failure(.transport("offline")))
        )

        await model.refresh()

        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
    }

    @Test("A failed refresh preserves a local catalogue")
    func preservesLocalDataOnRefreshFailure() async {
        let local = [technique(slug: "cached")]
        let model = TechniqueListModel(
            techniques: StubReader(local: local, result: .failure(.transport("offline")))
        )

        await model.loadIfNeeded()
        await model.refresh()

        guard case let .loaded(techniques) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(techniques == local)
    }
}
