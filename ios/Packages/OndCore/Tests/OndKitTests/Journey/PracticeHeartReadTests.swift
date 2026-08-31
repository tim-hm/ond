import Foundation
@testable import OndKit
import Testing

/// The heart rate around the last few practices: who may read it, when it is read
/// again, and what silence means. Its own suite beside the coach's trends, because
/// the questions differ — that one is about what a request carries, and this is
/// about what a card draws — and because both go through the same `isReadable`
/// gate, which is the one thing worth proving twice.
@MainActor
@Suite("The heart around a practice")
struct PracticeHeartReadTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_777_000_000)

    private func defaults() throws -> UserDefaults {
        let suite = "practice.heart.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    private func model(
        store: ScriptedHealthStore,
        defaults: UserDefaults,
        tier: SubscriptionTier = .plus
    ) -> HealthContextModel {
        HealthContextModel(
            store: store,
            defaults: defaults,
            now: { Self.now },
            entitledTier: { tier }
        )
    }

    private static func practice(minutesAgo: Double) -> SessionRecord {
        HomeFixtures.session(at: now.addingTimeInterval(-minutesAgo * 60), lasting: .seconds(300))
    }

    /// The gate that makes the whole feature legitimate: the switch is off, so
    /// Health is not asked — proven by the call count rather than by an empty
    /// answer, which a refused grant would also produce.
    @Test("With the opt-in off, no heart rate is read")
    func theHeartIsNotReadWithoutTheOptIn() async throws {
        let store = ScriptedHealthStore()
        let model = try model(store: store, defaults: defaults())

        await model.loadPracticeHeart(from: [Self.practice(minutesAgo: 30)])

        #expect(model.practiceHeart == nil)
        #expect(await store.queries == 0)
    }

    /// The other half of `isReadable`, and the reason it is one property: a
    /// lapsed subscriber who left the switch on must not keep the card.
    @Test("Below the tier, no heart rate is read even with the opt-in on")
    func theHeartIsNotReadBelowTheTier() async throws {
        let store = ScriptedHealthStore()
        let model = try model(store: store, defaults: defaults(), tier: .free)
        model.coachReadsHealthTrends = true

        await model.loadPracticeHeart(from: [Self.practice(minutesAgo: 30)])

        #expect(model.practiceHeart == nil)
        #expect(await store.queries == 0)
    }

    @Test("With the opt-in on, the practices are read and folded")
    func theHeartIsReadAndFolded() async throws {
        let recent = Self.practice(minutesAgo: 30)
        let earlier = Self.practice(minutesAgo: 300)
        let store = try ScriptedHealthStore(heartRates: [
            HeartFixtures.reading(for: recent, 71),
            HeartFixtures.reading(for: earlier, 64),
        ])
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        await model.loadPracticeHeart(from: [recent, earlier])

        #expect(model.practiceHeart?.marks.map(\.beatsPerMinute) == [64, 71])
    }

    /// Too little to say anything is the same silence as not being allowed to
    /// look: the card is not mounted either way.
    @Test("One reading is not drawn")
    func oneReadingLeavesNothingToDraw() async throws {
        let recent = Self.practice(minutesAgo: 30)
        let store = try ScriptedHealthStore(heartRates: [HeartFixtures.reading(for: recent, 71)])
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        await model.loadPracticeHeart(from: [recent, Self.practice(minutesAgo: 300)])

        #expect(model.practiceHeart == nil)
    }

    /// Freshness is keyed on the practices as well as the clock. A session
    /// finished twenty seconds ago is exactly when somebody looks, and time
    /// alone would answer them with the read that preceded it.
    @Test("A repeat ask is served from the last read; a new session is not")
    func freshnessIsKeyedOnThePracticesAsWellAsTheClock() async throws {
        let recent = Self.practice(minutesAgo: 30)
        let earlier = Self.practice(minutesAgo: 300)
        let justFinished = Self.practice(minutesAgo: 1)
        let store = try ScriptedHealthStore(heartRates: [
            HeartFixtures.reading(for: recent, 71),
            HeartFixtures.reading(for: earlier, 64),
            HeartFixtures.reading(for: justFinished, 80),
        ])
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        await model.loadPracticeHeart(from: [recent, earlier])
        await model.loadPracticeHeart(from: [recent, earlier])
        #expect(await store.queries == 1)

        await model.loadPracticeHeart(from: [recent, earlier, justFinished])
        #expect(await store.queries == 2)
        #expect(model.practiceHeart?.marks.count == 3)
    }

    /// Withdrawing the opt-in blanks what is drawn, on the same terms as the
    /// trends beside it — the next request carries nothing and the card goes.
    @Test("Switching the opt-in off blanks the heartline")
    func withdrawingTheOptInBlanksTheHeartline() async throws {
        let recent = Self.practice(minutesAgo: 30)
        let earlier = Self.practice(minutesAgo: 300)
        let store = try ScriptedHealthStore(heartRates: [
            HeartFixtures.reading(for: recent, 71),
            HeartFixtures.reading(for: earlier, 64),
        ])
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true
        await model.loadPracticeHeart(from: [recent, earlier])
        #expect(model.practiceHeart != nil)

        model.coachReadsHealthTrends = false

        #expect(model.practiceHeart == nil)
    }
}
