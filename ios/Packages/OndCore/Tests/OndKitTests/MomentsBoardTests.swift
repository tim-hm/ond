import Foundation
@testable import OndKit
import Testing

/// The Moments tab's join: the routing layer resolved against the catalogue
/// the apps actually ship.
@Suite("The moments board")
struct MomentsBoardTests {
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

    private static let catalogue = OccasionCatalogue(occasions: occasions)

    private func board(
        occasions: OccasionCatalogue = MomentsBoardTests.catalogue
    ) -> MomentsBoard {
        MomentsBoard(techniques: SeededCatalogue.techniques, occasions: occasions)
    }

    // MARK: the join

    /// Seeded order, not goal order and not the catalogue's — the server decides
    /// which moment somebody is likeliest to want, and the tab does not
    /// second-guess it.
    @Test("Moments keep the order the occasions arrived in")
    func momentsKeepSeededOrder() {
        #expect(board().moments.map(\.title) == [
            "Before a presentation",
            "Through this meeting",
            "Winding down",
        ])
    }

    @Test("A moment naming an exercise nobody ships is dropped rather than drawn")
    func anUnresolvableSlugIsDropped() {
        #expect(!board().moments.contains { $0.id == "occasions/gone-fishing" })
    }

    /// The load-bearing half of a moment. Two moments reach for the same pace
    /// and differ only in how loudly they run and how long they run for, so a
    /// join that lost either would collapse them into one row.
    @Test("The prescription's session, register and surface travel with the stop")
    func thePrescriptionTravels() throws {
        let board = board()
        let presentation = try #require(board.moments.first)
        let meeting = try #require(board.moments.dropFirst().first)

        #expect(presentation.dialled != presentation.technique)
        // The length printed and the length played are one number: the duration
        // is a target to fit whole cycles into, so what the row states has to
        // come off the dialled technique rather than off the prescription.
        #expect(presentation.duration == presentation.dialled.plannedDuration)
        #expect(presentation.surface == .fullScreen)
        #expect(presentation.register == .plain)
        #expect(meeting.surface == .discreet)
        #expect(meeting.register == .playful)
    }

    /// A prescription is a target to fit whole cycles into, not a stopwatch to
    /// cut a breath short with.
    @Test("A moment fits whole cycles towards the length it asks for")
    func theMomentFitsWholeCyclesIntoTheAskedForLength() {
        let coherent = SeededCatalogue.technique("coherent-breathing")
        let asked = Duration.seconds(300)
        let played = Self.prescription(
            "coherent-breathing",
            goal: .calm,
            minutes: 5
        ).dialled(coherent).plannedDuration
        let cycle = coherent.stages[0].cycleDuration
        // Whole cycles only, so the fit is within half a breath either way.
        #expect(abs(played.milliseconds - asked.milliseconds) <= cycle.milliseconds / 2)
    }

    /// The other half of that rule, and why a row has to read its length off the
    /// dialled technique rather than off the prescription: a staged moment is
    /// counted in rounds, so an occasion asking for two minutes gets whatever the
    /// rounds actually are.
    @Test("A staged moment keeps its own length rather than being stretched")
    func aStagedTechniqueKeepsItsShape() {
        let staged = SeededCatalogue.technique("wim-hof-rounds")

        #expect(Self.prescription(
            "wim-hof-rounds",
            goal: .energy,
            minutes: 2
        ).dialled(staged) == staged)
    }

    /// A duplicate slug is something the server is documented as free to send,
    /// and two stops sharing an id is a `ForEach` with undefined behaviour.
    /// `DialStop`'s factories coalesce it so no fold has to remember.
    @Test("A route list with a repeated entry is one stop, not two sharing an identity")
    func aRepeatedOccasionIsOneStop() {
        let doubled = OccasionCatalogue(occasions: Self.occasions + [Self.occasions[0]])
        let board = board(occasions: doubled)

        #expect(Set(board.moments.map(\.id)).count == board.moments.count)
        #expect(board.moments.count == self.board().moments.count)
    }

    /// The wrist's whole screen, read off the shared join rather than a second
    /// one hand-rolled on the other device.
    @Test("The discreet moments are the ones only a wrist can deliver")
    func theDiscreetMomentsAreSeparable() {
        #expect(board().delivered(on: .discreet).map(\.title) == ["Through this meeting"])
        #expect(board().delivered(on: .fullScreen)
            .map(\.title) == ["Before a presentation", "Winding down"])
    }

    /// An occasion borrows a goal rather than reading the technique's, so what a
    /// moment is for cannot move because a technique was re-grouped.
    @Test("A moment wears the goal its prescription borrowed")
    func theGoalIsThePrescriptions() throws {
        let meeting = try #require(board().moments.dropFirst().first)

        #expect(meeting.goal == .focus)
        #expect(meeting.technique.goal == .calm)
    }

    /// What a build whose bundled export could not be read holds. Rare, and
    /// still a state the tab draws its own copy for rather than one it can
    /// wait out.
    @Test("No occasions is an empty board, not a degraded one")
    func noOccasionsIsAnEmptyBoard() {
        let board = board(occasions: .none)

        #expect(board.isEmpty)
        #expect(board.goals.isEmpty)
    }

    /// The occasions are the whole of this join. `OccasionCatalogue` still carries the
    /// progression, so this is the guard against a second band arriving back
    /// here — a slug the catalogue resolves, drawing nothing.
    @Test("The board is built from the occasions alone, never the progression")
    func onlyTheOccasionsBuildTheBoard() {
        let occasions = OccasionCatalogue(progression: [
            ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ])
        let board = board(occasions: occasions)

        #expect(board.isEmpty)
        #expect(board.goals.isEmpty)
    }

    // MARK: the filter

    @Test("No goal chosen is the whole board")
    func noGoalIsTheWholeBoard() {
        #expect(board().filtered(by: nil) == board().moments)
    }

    @Test("A goal narrows the moments")
    func aGoalNarrowsTheMoments() {
        let calm = board().filtered(by: .calm)

        #expect(calm.map(\.title) == ["Before a presentation"])
        #expect(calm.allSatisfy { $0.goal == .calm })
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
    @Test("The offered goals keep the enum's order rather than the occasions'")
    func theGoalsKeepTheEnumOrder() {
        #expect(board().goals == [.calm, .sleep, .focus])
    }
}
