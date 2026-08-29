import Foundation
@testable import OndKit
import Testing

/// The measurement that reads backwards. Every other number in this app
/// is better when it is bigger, so the tests worth having are the ones
/// that would still pass if `min` were `max` nowhere but here — the
/// personal best, the verdict on the result screen, and the number the
/// card shows.
@Suite("Resting rate")
struct RestingRateTests {
    @Test("The personal best is the slowest measured, not the most recent")
    func theLowestIsTheBest() async {
        let store = RateSpy([
            RestingRate(breathsPerMinute: 16),
            RestingRate(breathsPerMinute: 11),
            RestingRate(breathsPerMinute: 14),
        ])

        #expect(await store.lowest() == 11)
    }

    @Test("Nothing measured is no best, rather than a zero")
    func nothingMeasuredIsNoBest() async {
        #expect(await RateSpy().lowest() == nil)
    }
}

/// What the journey model does with a rate somebody has just counted.
@MainActor
@Suite("Recording a resting rate")
struct RestingRateRecordingTests {
    private func model(over rates: [RestingRate] = []) -> (JourneyModel, RateSpy) {
        let store = RateSpy(rates)
        let sessions = SessionSpy()
        let journeys = ServerSpy()
        let queue = SessionSyncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            rates: store,
            journeys: journeys,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        return (
            JourneyModel(
                sessions: sessions,
                scores: ScoreSpy(),
                rates: store,
                journeys: journeys,
                queue: queue
            ),
            store
        )
    }

    @Test("The first measurement is a personal best")
    func theFirstIsABest() async {
        let (model, store) = model()

        #expect(await model.record(restingBreaths: 15))
        #expect(model.lowestRestingRate == 15)
        #expect(await store.stored.count == 1)
    }

    /// The whole point of the type: a *lower* number is the better one, so a
    /// higher one is not a personal best however much bigger it is.
    @Test("A slower rate is a best and a faster one is not")
    func onlyASlowerRateIsABest() async {
        let (model, _) = model()

        _ = await model.record(restingBreaths: 14)
        #expect(await model.record(restingBreaths: 11), "slower than 14")
        #expect(model.lowestRestingRate == 11)

        #expect(await model.record(restingBreaths: 18) == false, "faster than 11")
        #expect(model.lowestRestingRate == 11, "and the card still shows the slowest")
    }

    /// A refresh folds the store rather than trusting what the last recording
    /// left behind — which is what makes the card right after a reinstall, and
    /// after a measurement taken on a device this one has not heard from.
    @Test("A refresh reads the slowest from the store")
    func aRefreshFoldsTheStore() async {
        let (model, _) = model(over: [
            RestingRate(breathsPerMinute: 19),
            RestingRate(breathsPerMinute: 12),
        ])

        await model.refresh()

        #expect(model.lowestRestingRate == 12)
    }
}

/// The rates take the same road to the server the pauses do, and the ledger
/// keeps them apart.
@Suite("Syncing resting rates")
struct RestingRateSyncTests {
    @Test("A rate is sent once and never again")
    func aRateIsSentOnce() async {
        let rates = RateSpy([RestingRate(breathsPerMinute: 13)])
        let server = ServerSpy()
        let queue = SessionSyncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy(),
            rates: rates,
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        #expect(await server.receivedRates.count == 1)

        await queue.sync()
        #expect(await server.receivedRates.count == 1, "a second run has nothing to say")

        await rates.record(RestingRate(breathsPerMinute: 12))
        await queue.sync()
        #expect(await server.receivedRates.count == 2, "and picks up what arrived since")
    }

    /// The two measurements have separate ledger keys, so acknowledging one
    /// cannot mark the other sent. They are different files with independently
    /// minted ids, and a shared key would let a pause suppress a rate.
    @Test("A failed rate send leaves the pause ledger alone, and is retried")
    func aFailedSendIsRetried() async {
        let store = syncDefaults()
        let server = ServerSpy(isReachable: false)
        let queue = SessionSyncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy([BoltScore(seconds: 22)]),
            rates: RateSpy([RestingRate(breathsPerMinute: 13)]),
            journeys: server,
            ledger: SyncLedger(defaults: store)
        )

        await queue.sync()
        #expect(await server.receivedRates.isEmpty)
        // Absent rather than empty: a run that acknowledged nothing writes
        // nothing at all, so a failed send does not even mint the key.
        #expect(store.stringArray(forKey: "journey.acknowledgedRestingRates") == nil)

        await server.comeBackOnline()
        await queue.sync()
        #expect(await server.receivedRates.count == 1)
        #expect(await server.receivedScores.count == 1)
        #expect(store.stringArray(forKey: "journey.acknowledgedRestingRates")?.count == 1)
    }

    /// Erasing is erasing: the ledger cannot be left holding ids for rows the
    /// server no longer has, or the next sync sends nothing for a history that
    /// has to be rebuilt from scratch.
    @Test("Erasing forgets the rate ledger too")
    func erasingForgetsTheRateLedger() async {
        let store = syncDefaults()
        let queue = SessionSyncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy(),
            rates: RateSpy([RestingRate(breathsPerMinute: 13)]),
            journeys: ServerSpy(),
            ledger: SyncLedger(defaults: store)
        )

        await queue.sync()
        #expect(store.stringArray(forKey: "journey.acknowledgedRestingRates")?.count == 1)

        await queue.erase()
        #expect(store.stringArray(forKey: "journey.acknowledgedRestingRates") == nil)
    }
}
