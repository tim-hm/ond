import Foundation
@testable import OndKit
import Testing

/// What the offer suite works against and is not about.
///
/// The catalogue is the one the apps actually ship, so a slug that stops
/// resolving fails here rather than showing up as a row that quietly vanished.
enum OfferFixtures {
    /// A catalogue entry nothing routes to: no goal's first, so a star or a
    /// choice is the only way it reaches Home.
    static let unrouted = SeededCatalogue.technique("humming-breath")

    /// One exercise somebody composed, on a slug no seeded technique uses.
    /// `origin` is stated rather than defaulted because it is the whole of what
    /// `DialStop.id(of:)` reads to answer which band this exercise's row lives
    /// in.
    static let authored = Technique(
        id: "mine",
        slug: "mine",
        name: "My own square",
        summary: "Four counts, four ways.",
        goal: .calm,
        stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
        recommendedRounds: 1,
        origin: .personal
    )

    static func offer(
        starred: Set<DialStop.ID> = [],
        goals: [TechniqueGoal] = [],
        choice: HomeChoice? = nil,
        dialled: [TechniqueSlug: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) throws -> HomeOffer {
        try #require(HomeOffer(
            techniques: SeededCatalogue.techniques,
            authored: authored,
            starred: starred,
            goals: goals,
            choice: choice,
            dialled: dialled
        ))
    }
}
