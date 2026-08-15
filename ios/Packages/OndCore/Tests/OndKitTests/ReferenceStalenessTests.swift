import Foundation
@testable import OndKit
import Testing

/// When a reference model asks the server again without being told to.
///
/// The models publish local data and refresh behind it, which answered "load on
/// launch" but not "notice that the catalogue changed": once a model reached
/// `.loaded` nothing asked again for the life of the process. These are the two
/// halves of the window that ends that — quiet while fresh, asking once stale —
/// and the guarantee that neither costs the screen what it is already drawing.
@MainActor
@Suite("Refreshing reference data that has gone stale")
struct ReferenceStalenessTests {
    /// Always has an answer locally and counts how often it was asked for a
    /// fresh one. On the main actor so `settle` can read the count without
    /// awaiting, which is what lets a fire-and-forget background refresh be
    /// observed at all.
    @MainActor
    private final class CountingCatalogue: TechniqueReading {
        private(set) var refreshes = 0
        private let techniques: [Technique]

        init(techniques: [Technique]) {
            self.techniques = techniques
        }

        func localTechniques() async -> [Technique]? {
            techniques
        }

        func refreshTechniques() async throws -> [Technique] {
            refreshes += 1
            return techniques
        }
    }

    private func reader() -> CountingCatalogue {
        CountingCatalogue(techniques: [
            Technique(
                id: "box-breathing",
                slug: "box-breathing",
                name: "Box breathing",
                summary: "",
                goal: .calm,
                stages: [Stage(
                    phases: [Phase(kind: .inhale, duration: .seconds(4))],
                    cycles: 4
                )],
                recommendedRounds: 1
            ),
        ])
    }

    /// What the window buys. `loadIfNeeded` runs on every `.task`, so without it
    /// walking between tabs all evening would be a request per screen visit.
    @Test("A model holding fresh data does not ask the server again")
    func staysQuietWhileFresh() async {
        let reader = reader()
        let model = TechniqueListModel(techniques: reader)

        // Awaited rather than left to `loadIfNeeded`'s background task, so what
        // follows is measuring the window rather than racing the first request.
        await model.refresh()
        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(reader.refreshes == 1)
    }

    /// The half that was missing: a phone left open across a deployment kept
    /// drawing the copy it woke up with.
    ///
    /// The second assertion is the rule that makes the first one safe — the
    /// stale check starts a refresh *behind* what is drawn rather than putting a
    /// spinner over it, which is what a first load with local data already does.
    /// Asserted here rather than in a second test, because a test that reached
    /// this point separately would have to repeat every line above it to get
    /// there.
    @Test("A model holding stale data asks again without taking the screen down")
    func asksAgainOnceStale() async throws {
        let reader = reader()
        let model = TechniqueListModel(techniques: reader, freshFor: .zero)

        await model.refresh()
        #expect(reader.refreshes == 1)

        await model.loadIfNeeded()
        try await settle { reader.refreshes == 2 }

        #expect(reader.refreshes == 2)
        guard case let .loaded(techniques) = model.state else {
            Issue.record("expected the catalogue to stay drawn through the refresh")
            return
        }
        #expect(techniques.map(\.slug) == ["box-breathing"])
    }
}
