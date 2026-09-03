import Foundation
@testable import OndKit
import Testing

/// What the wrist may put in front of somebody. One rule, read by the front
/// door, the carousel and the moments list — the third was missed when each
/// filtered for itself, so the rule is pinned here rather than at any of them.
@Suite("What a wrist may offer")
struct WristCatalogueTests {
    private static func technique(_ slug: TechniqueSlug, requires: SubscriptionTier) -> Technique {
        Technique(
            id: TechniqueId(rawValue: slug.rawValue),
            slug: slug,
            name: slug.rawValue,
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
            requires: requires
        )
    }

    private static let catalogue = [
        technique("free-one", requires: .free),
        technique("paid-one", requires: .plus),
    ]

    @Test("A free wrist keeps only what it can start")
    func freeDropsThePaidOne() {
        #expect(Self.catalogue.unlocked(for: .free).map(\.slug) == ["free-one"])
    }

    @Test("A subscribed wrist keeps both, in the catalogue's order")
    func plusKeepsEverything() {
        #expect(Self.catalogue.unlocked(for: .plus).map(\.slug) == ["free-one", "paid-one"])
    }

    @Test("Every seeded exercise reaches a free wrist")
    func theSeedIsFreeThroughout() {
        let seeded = SeededCatalogue.techniques
        #expect(seeded.unlocked(for: .free).count == seeded.count)
    }
}
