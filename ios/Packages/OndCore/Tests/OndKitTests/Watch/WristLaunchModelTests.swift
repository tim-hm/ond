import Foundation
@testable import OndKit
import Testing

/// The phone's half of the handoff exchange: one order out, one conclusion
/// back, never a spinner that spins forever. The failure this model exists
/// for is silence — a wrist that is off, unpaired or missing the app produces
/// no event at all — and every wrong transition is a sheet lying: "sending"
/// over a failed launch, or "running" concluded by an abandoned order's ack.
@MainActor
@Suite("Wrist launch model")
struct WristLaunchModelTests {
    /// One assembled exchange: the model, the rig its orders ride, and the clock
    /// its timeout runs on.
    @MainActor
    private struct Exchange {
        let model: WristLaunchModel
        let orders: PlacedOrders
        let clock: ManualClock

        var pushes: Int {
            orders.pushes
        }

        func ridingOrder() async -> WatchSessionOrder? {
            await orders.riding()
        }

        /// Sends the meeting occasion, the one discreet route in the seed.
        func launch() {
            model.launch(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            )
        }

        /// Lets the ack timeout expire, and waits for the model to say so.
        func expire() async throws {
            clock.advance(by: WristLaunchModel.ackTimeout + .seconds(1))
            try await settle { model.phase != .sending }
        }

        /// Runs the timeout past its deadline where the exchange has already
        /// concluded, and gives whatever might still be waiting a moment to act, so
        /// the assertion reads a settled model. A nap rather than `settle` because
        /// what is under test is that nothing happens: there is no condition to poll,
        /// and a wait erring short can only under-detect a bug, never invent one.
        func settleWithoutChange() async throws {
            clock.advance(by: WristLaunchModel.ackTimeout + .seconds(1))
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func exchange(launches: Bool, tier: SubscriptionTier = .plus) -> Exchange {
        let orders = PlacedOrders(tier: tier)
        let clock = ManualClock()
        let model = WristLaunchModel(
            outbox: orders.outbox,
            launcher: ScriptedLauncher(launches: launches),
            push: { orders.pushed() },
            clock: clock
        )
        return Exchange(model: model, orders: orders, clock: clock)
    }

    /// The order has to be in the context before the launch call, which carries
    /// no payload of its own — and the phase has to be set in the same tap, or
    /// the sheet opening over it has a frame with nothing true to say.
    @Test("A launch places the order, pushes the context, and reports sending")
    func sendsTheOrderOut() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()

        #expect(exchange.model.phase == .sending)
        #expect(exchange.pushes == 1)
        let riding = try #require(await exchange.ridingOrder())
        #expect(
            riding.errand == .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            )
        )
    }

    @Test("The wrist's yes concludes the exchange as running")
    func concludesOnAnAcceptedAck() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        let riding = try #require(await exchange.ridingOrder())
        exchange.model.acknowledge(WatchOrderAck(orderId: riding.id, accepted: true))

        #expect(exchange.model.phase == .running)
        #expect(
            await exchange.ridingOrder() == nil,
            "a delivered order has done its work and leaves the context"
        )

        // The timeout is still out there, and must find nothing to conclude.
        try await exchange.settleWithoutChange()
        #expect(exchange.model.phase == .running)
    }

    /// The wrist saying no — most plausibly a catalogue that cannot resolve the
    /// ordered technique. Same copy as silence, but reached at once.
    @Test("The wrist declining concludes the exchange as failed")
    func concludesOnADeclinedAck() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        let riding = try #require(await exchange.ridingOrder())
        exchange.model.acknowledge(WatchOrderAck(orderId: riding.id, accepted: false))

        #expect(exchange.model.phase == .failed)
        #expect(await exchange.ridingOrder() == nil)
    }

    /// The silence case, and the reason the model exists: nothing answers, and
    /// the sheet must stop claiming progress on its own.
    @Test("An unanswered launch fails when the timeout passes")
    func timesOutIntoFailed() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        try await exchange.expire()

        #expect(exchange.model.phase == .failed)
        #expect(
            await exchange.ridingOrder() == nil,
            "an order nobody answered must not ride the next ordinary push"
        )
    }

    /// The system can refuse the launch outright — no paired watch, no watch
    /// app — and that answer arrives on its own, without the timeout's theatre.
    @Test("A refused launch fails without waiting out the timeout")
    func failsFastOnARefusedLaunch() async throws {
        let exchange = exchange(launches: false)

        exchange.launch()
        try await settle { exchange.model.phase == .failed }

        #expect(exchange.model.phase == .failed)
        #expect(await exchange.ridingOrder() == nil)
    }

    /// An ack that outlives its exchange answers an order the timeout already
    /// gave up on. The person has read the fallback; the sheet must not flip
    /// to "running" behind their thumb.
    @Test("An ack for an abandoned order concludes nothing")
    func ignoresAStaleAck() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        let abandoned = try #require(await exchange.ridingOrder())
        try await exchange.expire()

        exchange.model.acknowledge(WatchOrderAck(orderId: abandoned.id, accepted: true))

        #expect(exchange.model.phase == .failed)
    }

    /// Dismissing mid-flight is the person walking away. Whatever was riding
    /// the context is withdrawn, and the model is idle for the next tap.
    @Test("Dismissing withdraws the in-flight order and resets to idle")
    func dismissWithdrawsAndResets() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        exchange.model.dismiss()

        #expect(exchange.model.phase == nil)
        #expect(await exchange.ridingOrder() == nil)

        try await exchange.settleWithoutChange()
        #expect(exchange.model.phase == nil, "the abandoned timeout concludes nothing")
    }

    /// The wrist runs one session at a time, and the sheet reports one
    /// exchange. A second tap through a sheet already open must not mint a
    /// second order for the first one's ack to answer.
    @Test("A second launch while one is in flight is a no-op")
    func refusesASecondLaunch() async throws {
        let exchange = exchange(launches: true)

        exchange.launch()
        let first = try #require(await exchange.ridingOrder())
        exchange.launch()

        #expect(exchange.pushes == 1)
        exchange.model.acknowledge(WatchOrderAck(orderId: first.id, accepted: true))
        #expect(exchange.model.phase == .running)
    }

    /// Sending a session to the wrist is what önd+ buys, and the refusal has to be its
    /// own conclusion rather than `failed`: nothing went wrong, retrying will not help,
    /// and the sheet's next move is an offer rather than a walk to the watch. Nothing
    /// is launched and nothing rides the context, so a wrist that happens to be awake
    /// is not woken for an errand that is not coming.
    @Test("A launch below the subscription concludes as locked")
    func refusesToLaunchBelowTheSubscription() async {
        let exchange = exchange(launches: true, tier: .free)

        exchange.launch()

        #expect(exchange.model.phase == .locked)
        #expect(exchange.pushes == 0)
        #expect(await exchange.ridingOrder() == nil)
    }
}
