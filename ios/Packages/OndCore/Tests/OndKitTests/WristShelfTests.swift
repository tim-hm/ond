import Foundation
@testable import OndKit
import Testing

/// What the watch's front door offers before anybody has scrolled anywhere.
@Suite("The wrist's shelf")
struct WristShelfTests {
    private static let catalogue = SeededCatalogue.techniques

    private func shelf(_ history: [SessionRecord]) -> WristShelf {
        WristShelf(techniques: Self.catalogue, history: history)
    }

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
}
