import Foundation
@testable import OndKit
import Testing

/// What both shelf suites need and neither is about.
///
/// Its own type for the reason `HomeFixtures` is: the occasions each suite works
/// against are the setup rather than the subject, and two copies of them drift
/// on the fields nobody asserts. The catalogue is the one the apps actually
/// ship, so a slug that stops resolving fails here rather than showing up as a
/// row that quietly vanished.
enum ShelfFixtures {
    static func prescription(
        _ slug: String,
        goal: TechniqueGoal,
        minutes: Int = 5
    ) -> Prescription {
        Prescription(
            techniqueSlug: slug,
            goal: goal,
            surface: .fullScreen,
            duration: .seconds(minutes * 60)
        )
    }

    static let occasions = [
        Occasion(
            slug: "winding-down",
            name: "Winding down",
            summary: "Long, slow out-breaths.",
            prescription: prescription("extended-exhale", goal: .sleep)
        ),
    ]

    static let progression = [
        ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ProgressionStep(techniqueSlug: "physiological-sigh", note: "Seconds long."),
        ProgressionStep(techniqueSlug: "extended-exhale", note: "The lever underneath."),
    ]

    static let catalogue = OccasionCatalogue(occasions: occasions, progression: progression)

    /// A catalogue entry nothing routes to: no protocol prescribes it and it is
    /// on no rung, so a star is the only way it reaches Home.
    static let unrouted = SeededCatalogue.technique("coherent-breathing")

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

    /// Fourteen hundred by default, which `HomeSuggestion` reads as `focus` — a
    /// goal no protocol here borrows, so the suggestion is a known fallback
    /// rather than whatever the clock decided.
    static func shelf(
        starred: Set<DialStop.ID> = [],
        history: [SessionRecord] = [],
        hour: Int = 14,
        occasions: OccasionCatalogue = ShelfFixtures.catalogue,
        dialled: [String: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) -> HomeShelf {
        HomeShelf(
            techniques: SeededCatalogue.techniques,
            occasions: occasions,
            history: history,
            starred: starred,
            hour: hour,
            dialled: dialled,
            authored: authored
        )
    }
}
