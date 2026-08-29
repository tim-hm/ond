import Foundation
@testable import OndKit
import Testing

/// The wrist's one chance to decline an order the phone placed. The two
/// resolutions are deliberately asymmetric and the asymmetry is invisible: a
/// technique this build does not hold means nothing to breathe, where an
/// occasion it cannot see means only that its routes are behind the phone's —
/// and the phone has already decided the session is worth running.
@Suite("Ordered moment")
struct OrderedMomentTests {
    private static let meeting = Occasion(
        slug: "through-this-meeting",
        name: "Through this meeting",
        summary: "",
        prescription: Prescription(
            techniqueSlug: "coherent-breathing",
            goal: .calm,
            surface: .discreet,
            duration: .seconds(1800)
        )
    )

    private func order(technique: String) -> WatchSessionOrder {
        WatchSessionOrder(
            id: UUID(),
            errand: .breathe(occasionSlug: Self.meeting.slug, techniqueSlug: technique),
            issuedAt: .now
        )
    }

    @Test("An order this watch can resolve keeps the occasion's own name")
    func resolvesAgainstTheCatalogue() throws {
        let moment = try #require(
            OrderedMoment(
                order: order(technique: "coherent-breathing"),
                techniques: SeededCatalogue.techniques,
                occasions: [Self.meeting]
            )
        )

        #expect(moment.technique.slug == "coherent-breathing")
        #expect(moment.occasionName == "Through this meeting")
    }

    /// The refusal that matters: a phone running ahead of the watch's catalogue
    /// orders something this build has never heard of. Declining is what turns
    /// the phone's sheet into the sentence that names the way out.
    @Test("An order naming an unknown technique is refused")
    func refusesAnUnknownTechnique() {
        #expect(
            OrderedMoment(
                order: order(technique: "a-technique-this-build-never-shipped"),
                techniques: SeededCatalogue.techniques,
                occasions: [Self.meeting]
            ) == nil
        )
    }

    /// The softer half. The wrist fetches routes and catalogue separately, and
    /// a first launch with no signal has the bundled techniques but no routes at
    /// all — so an order must still run, under the exercise's own name.
    @Test("An order whose occasion this watch cannot see still runs")
    func fallsBackToTheTechniqueName() throws {
        let moment = try #require(
            OrderedMoment(
                order: order(technique: "coherent-breathing"),
                techniques: SeededCatalogue.techniques,
                occasions: []
            )
        )

        #expect(moment.occasionName == SeededCatalogue.technique("coherent-breathing").name)
    }

    /// The sheet presenting this is keyed to the exchange, not to what it
    /// resolved to: two orders for the same occasion are two sessions, and a
    /// view keyed on the technique would refuse to present the second.
    @Test("A moment is identified by its order")
    func isIdentifiedByTheOrder() throws {
        let placed = order(technique: "coherent-breathing")
        let moment = try #require(
            OrderedMoment(
                order: placed,
                techniques: SeededCatalogue.techniques,
                occasions: [Self.meeting]
            )
        )

        #expect(moment.id == placed.id)
    }
}
