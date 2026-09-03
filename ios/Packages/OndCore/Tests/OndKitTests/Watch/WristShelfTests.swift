import Foundation
@testable import OndKit
import Testing

/// What the watch's front door offers before anybody has scrolled anywhere.
@Suite("The wrist's shelf")
struct WristShelfTests {
    private static let catalogue = SeededCatalogue.techniques

    private func shelf(_ history: [SessionRecord]) -> WristShelf {
        WristShelf(techniques: Self.catalogue, history: history, tier: .free)
    }

    /// A catalogue of one paid exercise, so the gate is asserted against a
    /// technique this test priced rather than one the seed happens to hold —
    /// today it holds none, which is exactly why the rule needs pinning.
    private static let paid = Technique(
        id: "t",
        slug: "steady",
        name: "Steady",
        summary: "",
        goal: .calm,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(5)),
                    Phase(kind: .exhale, duration: .seconds(5)),
                ],
                cycles: 6
            ),
        ],
        recommendedRounds: 1,
        requires: .plus
    )

    private func slugs(_ history: [SessionRecord]) -> [TechniqueSlug] {
        shelf(history).stops.map(\.technique.slug)
    }

    @Test("A wrist that has breathed nothing still opens on the catalogue")
    func anEmptyHistoryFallsToTheCatalogue() {
        #expect(slugs([]) == Self.catalogue.prefix(WristShelf.capacity).map(\.slug))
    }

    @Test("The most recent exercise leads")
    func theMostRecentLeads() {
        let history = [
            HomeFixtures.session("box-breathing", at: Date(timeIntervalSince1970: 1000)),
            HomeFixtures.session("humming-breath", at: Date(timeIntervalSince1970: 2000)),
        ]

        #expect(slugs(history).first == "humming-breath")
    }

    @Test("One exercise breathed twice takes one card, not two")
    func repeatsAreFoldedTogether() {
        let history = (0 ..< 4).map {
            HomeFixtures.session(
                "box-breathing",
                at: Date(timeIntervalSince1970: Double(1000 + $0))
            )
        }

        let offered = slugs(history)
        #expect(offered.count == WristShelf.capacity)
        #expect(offered.filter { $0 == "box-breathing" } == ["box-breathing"])
    }

    @Test("A session whose exercise has left the catalogue offers no card")
    func aGoneExerciseIsSkipped() {
        let history = [HomeFixtures.session("deleted-exercise", at: .now)]

        #expect(!slugs(history).contains("deleted-exercise"))
        #expect(slugs(history).count == WristShelf.capacity)
    }

    @Test("History fills the shelf before the catalogue does, and never past it")
    func historyLeadsAndTheShelfIsBounded() {
        let history = [
            HomeFixtures.session("humming-breath", at: Date(timeIntervalSince1970: 4000)),
            HomeFixtures.session("cooling-breath", at: Date(timeIntervalSince1970: 3000)),
            HomeFixtures.session("bellows-breath", at: Date(timeIntervalSince1970: 2000)),
            HomeFixtures.session("box-breathing", at: Date(timeIntervalSince1970: 1000)),
        ]

        #expect(slugs(history) == ["humming-breath", "cooling-breath", "bellows-breath"])
    }

    /// Having breathed it is the case worth pinning: history is the shelf's
    /// first source, so a locked exercise that reached it once must still drop.
    @Test("A lapsed wrist is not offered an exercise it cannot start")
    func aPaidExerciseIsDroppedAtFree() {
        let history = [HomeFixtures.session("steady", at: Date(timeIntervalSince1970: 1000))]
        #expect(WristShelf(techniques: [Self.paid], history: history, tier: .free).stops.isEmpty)
    }

    @Test("The same exercise stands once the phone says it is paid for")
    func aPaidExerciseStandsAtPlus() {
        let shelf = WristShelf(techniques: [Self.paid], history: [], tier: .plus)
        #expect(shelf.stops.map(\.technique.slug) == ["steady"])
    }
}
