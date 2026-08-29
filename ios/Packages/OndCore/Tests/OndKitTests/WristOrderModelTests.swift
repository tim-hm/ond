import Foundation
@testable import OndKit
import Testing

/// The wrist's half of the handoff: what it takes up, what it declines, and the
/// fact that it always says which. Worth pinning because a wrist that decides
/// something and says nothing leaves the phone's sheet claiming progress for ten
/// seconds and then blaming the watch — and because "declined" and "accepted but
/// never shown" look identical from the phone while being opposite on the wrist.
@MainActor
@Suite("Wrist order model")
struct WristOrderModelTests {
    /// Answers locally with the seeded catalogue and whatever occasions it was
    /// given; refreshes can still be made unreachable independently.
    private final class ScriptedReader: TechniqueReading, OccasionReading, @unchecked Sendable {
        var occasions: OccasionCatalogue
        var isReachable: Bool

        init(occasions: OccasionCatalogue, isReachable: Bool) {
            self.occasions = occasions
            self.isReachable = isReachable
        }

        func localTechniques() async -> [Technique]? {
            SeededCatalogue.techniques
        }

        func refreshTechniques() async throws -> [Technique] {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return SeededCatalogue.techniques
        }

        func localOccasions() async -> OccasionCatalogue? {
            occasions
        }

        func refreshOccasions() async throws -> OccasionCatalogue {
            guard isReachable else {
                throw TechniqueRepositoryError.transport(.stub("connection refused"))
            }
            return occasions
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

    /// The model, and the occasions beside it — the scene loads those at launch,
    /// and a test that wants the occasion's own name has to say so too.
    private func model(
        on wrist: Wrist,
        reachable: Bool = true,
        occasions: [Occasion] = [meeting]
    ) -> (order: WristOrderModel, occasions: OccasionCatalogueModel) {
        let reader = ScriptedReader(
            occasions: OccasionCatalogue(occasions: occasions),
            isReachable: reachable
        )
        let occasions = OccasionCatalogueModel(occasions: reader)
        return (
            WristOrderModel(
                catalogue: TechniqueListModel(techniques: reader),
                occasions: occasions,
                isBusy: { wrist.isBusy },
                answer: { wrist.acks.append($0) }
            ),
            occasions
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
        let (model, occasions) = model(on: wrist)
        let placed = order()

        // As the scene does at launch, so the moment's own name is in hand.
        await occasions.loadIfNeeded()
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

    /// The occasions are read as they stand and never waited for, so a wrist whose
    /// only load is the bundled seed still runs the session — under the
    /// exercise's own name, which is `OrderedMoment`'s documented fallback.
    @Test("An order still runs when the occasions cannot be reached")
    func runsWithoutOccasions() async throws {
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
    /// session wants a heart rate now, and a wrist with no catalogue and no occasions
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

    /// Two orders arriving inside one resolution. Newly possible because the phone
    /// now has two independent producers — a tapped occasion and a session wanting
    /// a heart rate — and resolving a breathing errand suspends on the catalogue,
    /// so both could clear the guard, both be told yes, and the second overwrite
    /// the first's screen while the phone believed both were running.
    @Test("Two orders arriving together cannot both be taken up")
    func declinesASecondOrderMidResolution() async {
        let wrist = Wrist()
        let model = model(on: wrist).order

        async let first: Void = model.take(up: order())
        async let second: Void = model.take(up: order())
        _ = await (first, second)

        #expect(wrist.acks.count == 2, "both are answered")
        #expect(wrist.acks.count(where: \.accepted) == 1, "one wrist, one yes")
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
