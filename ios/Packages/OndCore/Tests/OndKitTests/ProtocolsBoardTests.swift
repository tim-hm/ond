import Foundation
@testable import OndKit
import Testing

/// The Protocols tab's join: the routing layer resolved against the catalogue
/// the apps actually ship.
@Suite("The protocols board")
struct ProtocolsBoardTests {
    private static func prescription(
        _ slug: String,
        goal: TechniqueGoal,
        surface: DeliverySurface = .fullScreen,
        register: CopyRegister = .plain,
        minutes: Int = 5
    ) -> Prescription {
        Prescription(
            techniqueSlug: slug,
            goal: goal,
            surface: surface,
            register: register,
            duration: .seconds(minutes * 60)
        )
    }

    /// Occasions in the shape the server sends them, including the pair that
    /// differ only in surface and one naming an exercise no build holds.
    private static let occasions = [
        Occasion(
            slug: "before-a-presentation",
            name: "Before a presentation",
            summary: "Steady the nerves.",
            prescription: prescription("box-breathing", goal: .calm, minutes: 3)
        ),
        Occasion(
            slug: "through-this-meeting",
            name: "Through this meeting",
            summary: "Nothing on screen, nothing to hear.",
            prescription: prescription(
                "coherent-breathing",
                goal: .focus,
                surface: .discreet,
                register: .playful
            )
        ),
        Occasion(
            slug: "gone-fishing",
            name: "Gone fishing",
            summary: "Nothing ships this.",
            prescription: prescription("an-exercise-nobody-ships", goal: .focus)
        ),
        Occasion(
            slug: "winding-down",
            name: "Winding down",
            summary: "Long, slow out-breaths.",
            prescription: prescription("extended-exhale", goal: .sleep)
        ),
    ]

    private static let progression = [
        ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ProgressionStep(techniqueSlug: "an-exercise-nobody-ships", note: "Nor this."),
        ProgressionStep(techniqueSlug: "physiological-sigh", note: ""),
    ]

    private static let routes = Routes(occasions: occasions, progression: progression)

    private func board(routes: Routes = ProtocolsBoardTests.routes) -> ProtocolsBoard {
        ProtocolsBoard(techniques: SeededCatalogue.techniques, routes: routes)
    }

    // MARK: the join

    /// Seeded order, not goal order and not the catalogue's — the server decides
    /// which moment somebody is likeliest to want, and the tab does not
    /// second-guess it.
    @Test("Protocols keep the order the routes arrived in")
    func protocolsKeepSeededOrder() {
        #expect(board().protocols.map(\.title) == [
            "Before a presentation",
            "Through this meeting",
            "Winding down",
        ])
    }

    @Test("A protocol naming an exercise nobody ships is dropped rather than drawn")
    func anUnresolvableSlugIsDropped() {
        #expect(!board().protocols.contains { $0.id == "occasions/gone-fishing" })
        #expect(!board().startHere.contains { $0.technique.slug == "an-exercise-nobody-ships" })
    }

    /// The load-bearing half of a protocol. Two moments reach for the same pace
    /// and differ only in how loudly they run and how long they run for, so a
    /// join that lost either would collapse them into one row.
    @Test("The prescription's dose, register and surface travel with the stop")
    func thePrescriptionTravels() throws {
        let board = board()
        let presentation = try #require(board.protocols.first)
        let meeting = try #require(board.protocols.dropFirst().first)

        #expect(presentation.dose != nil)
        // The length printed and the length played are one number: the dose is
        // a target to fit whole cycles into, so what the row states has to come
        // off the dialled technique rather than off the prescription.
        #expect(presentation.duration == presentation.dialled.plannedDuration)
        #expect(presentation.surface == .fullScreen)
        #expect(presentation.register == .plain)
        #expect(meeting.surface == .discreet)
        #expect(meeting.register == .playful)
    }

    /// An occasion borrows a goal rather than reading the technique's, so what a
    /// moment is for cannot move because a technique was re-grouped.
    @Test("A protocol wears the goal its prescription borrowed")
    func theGoalIsThePrescriptions() throws {
        let meeting = try #require(board().protocols.dropFirst().first)

        #expect(meeting.goal == .focus)
        #expect(meeting.technique.goal == .calm)
    }

    /// The sentence that makes an order a progression. An empty note falls back
    /// to the exercise's own summary, which is exactly what `ProgressionStep`
    /// documents empty as meaning.
    @Test("A rung says why it sits where it does, or borrows the exercise's summary")
    func aRungCarriesItsNote() {
        #expect(board().startHere.map(\.summary) == [
            "Start here.",
            SeededCatalogue.technique("physiological-sigh").summary,
        ])
    }

    /// Routes have no bundled seed, so this is a real first-launch state rather
    /// than a guard against one — and the tab draws its own copy for it.
    @Test("No routes is an empty board, not a degraded one")
    func noRoutesIsAnEmptyBoard() {
        let board = board(routes: .none)

        #expect(board.isEmpty)
        #expect(board.goals.isEmpty)
    }

    // MARK: the filter

    @Test("No goal chosen is the whole board")
    func noGoalIsTheWholeBoard() {
        #expect(board().filtered(by: nil) == board())
    }

    /// Both sections narrow together. A goal that left Start here showing every
    /// rung while the moments thinned out would read as a filter that half
    /// worked.
    @Test("A goal narrows the moments and the rungs alike")
    func aGoalNarrowsBothSections() {
        let calm = board().filtered(by: .calm)

        #expect(calm.protocols.map(\.title) == ["Before a presentation"])
        #expect(calm.startHere.map(\.technique.slug) == ["box-breathing"])
        #expect((calm.protocols + calm.startHere).allSatisfy { $0.goal == .calm })
    }

    @Test("A goal nothing on the board serves leaves nothing on it")
    func anAbsentGoalEmptiesTheBoard() {
        #expect(board().filtered(by: .energy).isEmpty)
    }

    /// The pills are drawn from this, so a pill that filtered to nothing would
    /// be a control offering an empty screen.
    @Test("The offered goals are the ones the board can actually narrow to")
    func theGoalsAreTheOnesPresent() {
        let board = board()

        #expect(board.goals.allSatisfy { !board.filtered(by: $0).isEmpty })
        #expect(TechniqueGoal.allCases.filter { !board.filtered(by: $0).isEmpty } == board.goals)
    }

    /// `TechniqueGoal`'s own order, so nothing reshuffles under somebody who has
    /// learned where sleep sits.
    @Test("The offered goals keep the enum's order rather than the routes'")
    func theGoalsKeepTheEnumOrder() {
        #expect(board().goals == [.calm, .sleep, .reset, .focus])
    }
}
