import Foundation
@testable import OndKit
import Testing

/// The wrist's half of the handoff: what it takes up, what it declines, and the
/// fact that it always says which.
///
/// Worth pinning because a wrist that decides something and says nothing leaves
/// the phone's sheet claiming progress for ten seconds and then blaming the
/// watch — and because "declined" and "accepted but never shown" look identical
/// from the phone while being opposite on the wrist.
@MainActor
@Suite("Wrist order model")
struct WristOrderModelTests {
    /// Answers with the seeded catalogue and whatever routes it was given, or
    /// refuses — a watch that cannot reach its server and holds no cache.
    private final class ScriptedReader: TechniqueReading, @unchecked Sendable {
        var routes: Routes
        var isReachable: Bool

        init(routes: Routes, isReachable: Bool) {
            self.routes = routes
            self.isReachable = isReachable
        }

        func listTechniques() async throws -> [Technique] {
            guard isReachable else {
                throw TechniqueRepositoryError.transport("connection refused")
            }
            return SeededCatalogue.techniques
        }

        func listFoundations() async throws -> [FoundationTopic] {
            []
        }

        func listRoutes() async throws -> Routes {
            guard isReachable else {
                throw TechniqueRepositoryError.transport("connection refused")
            }
            return routes
        }
    }

    /// What the wrist answered, and whether it is mid-session. A reference the
    /// model's two closures share with the test.
    @MainActor
    private final class Wrist {
        var acks: [WatchOrderAck] = []
        var isBusy = false
    }

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

    /// The model, and the routes beside it — the scene loads those at launch,
    /// and a test that wants the occasion's own name has to say so too.
    private func model(
        on wrist: Wrist,
        reachable: Bool = true,
        occasions: [Occasion] = [meeting]
    ) -> (order: WristOrderModel, routes: RoutesModel) {
        let reader = ScriptedReader(
            routes: Routes(occasions: occasions),
            isReachable: reachable
        )
        let routes = RoutesModel(routes: reader)
        return (
            WristOrderModel(
                catalogue: TechniqueListModel(techniques: reader),
                routes: routes,
                isBusy: { wrist.isBusy },
                answer: { wrist.acks.append($0) }
            ),
            routes
        )
    }

    private func order(technique: String = "coherent-breathing") -> WatchSessionOrder {
        WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: Self.meeting.slug,
                techniqueSlug: technique
            ),
            issuedAt: .now
        )
    }

    /// What the wrist is breathing, or nil for anything else — which is what most
    /// of these assertions are about, and reads better than a `case` per test.
    private func breathing(_ model: WristOrderModel) -> OrderedMoment? {
        guard case let .breathe(moment) = model.engagement else { return nil }
        return moment
    }

    @Test("An order this wrist can run is taken up and accepted")
    func takesUpAnOrder() async throws {
        let wrist = Wrist()
        let (model, routes) = model(on: wrist)
        let placed = order()

        // As the scene does at launch, so the moment's own name is in hand.
        await routes.loadIfNeeded()
        await model.take(up: placed)

        let moment = try #require(breathing(model))
        #expect(moment.order.id == placed.id)
        #expect(moment.occasionName == "Through this meeting")
        #expect(wrist.acks.map(\.accepted) == [true])
        #expect(wrist.acks.map(\.orderId) == [placed.id])
    }

    /// The phone runs ahead of this watch's catalogue. Declining is what turns
    /// the phone's sheet into the sentence naming the way out — and the wrist
    /// must present nothing, rather than a screen with no technique behind it.
    @Test("An order naming an unknown technique is declined, and nothing is shown")
    func declinesAnUnknownTechnique() async {
        let wrist = Wrist()
        let model = model(on: wrist).order

        await model.take(up: order(technique: "a-technique-this-build-never-shipped"))

        #expect(model.engagement == nil)
        #expect(wrist.acks.map(\.accepted) == [false])
    }

    /// The routes are read as they stand and never waited for, so a wrist whose
    /// only load is the bundled seed still runs the session — under the
    /// exercise's own name, which is `OrderedMoment`'s documented fallback.
    @Test("An order still runs when the routes cannot be reached")
    func runsWithoutRoutes() async throws {
        let wrist = Wrist()
        let model = model(on: wrist, occasions: []).order

        await model.take(up: order())

        let moment = try #require(breathing(model))
        #expect(moment.occasionName == SeededCatalogue.technique("coherent-breathing").name)
        #expect(wrist.acks.map(\.accepted) == [true])
    }

    /// Two cadences under one workout runtime would tap over each other, and the
    /// first screen to go away would release the budget from under the other. So
    /// a wrist mid-session says no — including to a session it started itself.
    @Test("A wrist already mid-session declines")
    func declinesWhileBusy() async {
        let wrist = Wrist()
        let model = model(on: wrist).order
        wrist.isBusy = true

        await model.take(up: order())

        #expect(model.engagement == nil)
        #expect(wrist.acks.map(\.accepted) == [false])
    }

    /// The same rule for the phone's own second order: the first is still
    /// presented, and `.sheet(item:)` would not compose a second over it — so
    /// accepting would have the phone say a session is running that is not.
    @Test("A second order while one is presented is declined")
    func declinesASecondOrder() async {
        let wrist = Wrist()
        let model = model(on: wrist).order
        let first = order()

        await model.take(up: first)
        await model.take(up: order())

        #expect(breathing(model)?.order.id == first.id, "the first is what is running")
        #expect(wrist.acks.map(\.accepted) == [true, false])
    }

    /// And once the screen has gone, the wrist is free again — otherwise one
    /// handoff would be all a launch ever accepted.
    @Test("A dismissed session leaves the wrist free for the next order")
    func acceptsAgainAfterDismissal() async {
        let wrist = Wrist()
        let model = model(on: wrist).order

        await model.take(up: order())
        model.dismiss()
        await model.take(up: order())

        #expect(model.engagement != nil)
        #expect(wrist.acks.map(\.accepted) == [true, true])
    }

    /// The other errand, and the reason it resolves against nothing: a phone
    /// session wants a heart rate now, and a wrist with no catalogue and no routes
    /// has everything it needs to give one.
    @Test("A wrist asked for its sensor takes it up with no catalogue at all")
    func takesUpASharingOrder() async {
        let wrist = Wrist()
        let model = model(on: wrist, reachable: false).order
        let placed = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)

        await model.take(up: placed)

        #expect(model.engagement == .sharePulse(placed))
        #expect(wrist.acks.map(\.accepted) == [true])
    }

    /// The wrist holds one workout budget, and a session somebody is breathing on
    /// it outranks a badge on their phone.
    @Test("A wrist sharing its sensor declines a session to breathe")
    func declinesASessionWhileSharing() async {
        let wrist = Wrist()
        let model = model(on: wrist).order

        await model.take(up: WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now))
        await model.take(up: order())

        #expect(breathing(model) == nil, "the sharing is what the wrist is engaged in")
        #expect(wrist.acks.map(\.accepted) == [true, false])
    }

    /// Every order is answered. A phone with a sheet open is waiting on exactly
    /// one message, and silence is the failure this model exists to prevent.
    @Test("Every order gets exactly one answer, whatever it resolves to")
    func alwaysAnswersOnce() async {
        let wrist = Wrist()
        let model = model(on: wrist).order

        await model.take(up: order())
        model.dismiss()
        await model.take(up: order(technique: "not-in-this-build"))
        wrist.isBusy = true
        await model.take(up: order())

        #expect(wrist.acks.count == 3)
    }
}
