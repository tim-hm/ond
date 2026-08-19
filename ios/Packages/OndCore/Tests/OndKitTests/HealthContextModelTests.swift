import Foundation
@testable import OndKit
import Testing

/// The opt-in state machine and the folding behind the coach's health context:
/// off means Health is never touched, on means the series fold through the
/// summary builder, and "nothing to say" is indistinguishable from "not
/// allowed to look" — the model never learns which it was.
@MainActor
@Suite("Coach health context")
struct HealthContextModelTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_777_000_000)

    /// A daily series: `value` on each of the last seven days, `baseline` on
    /// ten spread days before them — enough evidence for a trend by
    /// `HealthSummaryBuilder`'s own thresholds.
    private static func trendingSeries(recent value: Double, baseline: Double) -> [DailyQuantity] {
        let baselineDays = stride(from: -48, through: -12, by: 4).compactMap { offset in
            DailyQuantity(day: day(offset), value: baseline)
        }
        let recentDays = (-6 ... 0).compactMap { offset in
            DailyQuantity(day: day(offset), value: value)
        }
        return baselineDays + recentDays
    }

    private static func day(_ offset: Int) -> Date {
        now.addingTimeInterval(TimeInterval(offset) * 86400)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "health-context-tests.\(UUID().uuidString)"))
    }

    /// Subscribed unless a test says otherwise, because reading Health costs
    /// önd+ and this suite is about the folding rather than the gate. What the
    /// gate does is pinned by `aFreeTierReadsNothing` below, which is the one
    /// test here that passes `.free`.
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

    @Test("Opt-in off asks Health nothing and yields no context")
    func optInOffTouchesNothing() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let model = try model(store: store, defaults: defaults())

        #expect(await model.context() == nil)
        #expect(await store.queries == 0)
        #expect(await store.readAuthorizationRequests == 0)
    }

    /// Storing the preference and asking Health for access are two calls, on
    /// purpose — see the property. A screen that turns the switch on makes
    /// both, in that order, which is what this pins.
    @Test("Turning the opt-in on from a screen asks Health for read access")
    func optInOnRequestsAuthorization() async throws {
        let store = ScriptedHealthStore()
        let model = try model(store: store, defaults: defaults())

        model.coachReadsHealthTrends = true
        #expect(await store.readAuthorizationRequests == 0, "the setter asks for nothing")

        model.requestReadAccess()
        await model.authorizationRequest?.value

        #expect(await store.readAuthorizationRequests == 1)
    }

    @Test("Every series folds through the summary builder into one context")
    func seriesFoldIntoContext() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58),
            heartRateVariability: Self.trendingSeries(recent: 45, baseline: 51),
            respiratoryRate: Self.trendingSeries(recent: 13, baseline: 15)
        )
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        let context = try #require(await model.context())
        #expect(context.restingHeartRate == HealthSnapshot(sevenDayMean: 62, trendFromBaseline: 4))
        #expect(
            context.heartRateVariability
                == HealthSnapshot(sevenDayMean: 45, trendFromBaseline: -6)
        )
        #expect(
            context.sleepingBreathingRate
                == HealthSnapshot(sevenDayMean: 13, trendFromBaseline: -2)
        )
    }

    @Test("One silent metric leaves the other's evidence standing")
    func oneMetricSuffices() async throws {
        let store = ScriptedHealthStore(
            heartRateVariability: Self.trendingSeries(recent: 45, baseline: 51)
        )
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        let context = try #require(await model.context())
        #expect(context.restingHeartRate == nil)
        #expect(context.heartRateVariability?.sevenDayMean == 45)
        #expect(context.sleepingBreathingRate == nil)
    }

    /// A watch worn to bed but not to train reports breathing and neither heart
    /// series — so the breathing rate has to hold a context up alone, or the one
    /// figure practice actually moves would be dropped for want of a heartbeat.
    @Test("Breathing alone is evidence enough for a context")
    func breathingAloneMakesAContext() async throws {
        let store = ScriptedHealthStore(
            respiratoryRate: Self.trendingSeries(recent: 14, baseline: 14)
        )
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        let context = try #require(await model.context())
        #expect(context.sleepingBreathingRate?.sevenDayMean == 14)
        #expect(context.restingHeartRate == nil)
        #expect(context.heartRateVariability == nil)
    }

    /// Empty series are what a denied read grant answers too, so this test is
    /// the denied case as much as the no-data one — deliberately the same.
    @Test("Denied access or an empty Health store is no context")
    func emptyHealthIsNoContext() async throws {
        let model = try model(store: ScriptedHealthStore(), defaults: defaults())
        model.coachReadsHealthTrends = true

        #expect(await model.context() == nil)
    }

    @Test("The opt-in survives a relaunch, and restoring it re-asks nothing")
    func optInPersists() async throws {
        let defaults = try defaults()
        let first = ScriptedHealthStore()
        model(store: first, defaults: defaults).coachReadsHealthTrends = true

        let second = ScriptedHealthStore()
        let relaunched = model(store: second, defaults: defaults)

        #expect(relaunched.coachReadsHealthTrends)
        #expect(
            await second.readAuthorizationRequests == 0,
            "restoring a stored choice is not a new grant to ask for"
        )
    }

    /// The state the card exists for: opted in, and Health had nothing.
    ///
    /// Before this state was named, that person got a switch reading "on" that
    /// did nothing observable and never would — a refused grant looked exactly
    /// like a working one. It is deliberately the *same* state as an empty
    /// Health store, because HealthKit does not report a denied read and this
    /// app must not guess at one.
    @Test("Opted in with nothing to read is a state the screen can show")
    func optedInWithNothingIsNothingReadable() async throws {
        let store = ScriptedHealthStore()
        let model = try model(store: store, defaults: defaults())

        model.coachReadsHealthTrends = true
        model.requestReadAccess()
        await model.authorizationRequest?.value

        #expect(model.healthTrends == .nothingReadable)
        #expect(await store.queries == 3, "every series was genuinely asked for")
    }

    /// A screen that re-mounts its trends card asks again for itself — the
    /// model owns making that one set of queries rather than two.
    @Test("A read moments old serves the next asker without re-querying Health")
    func aFreshReadServesTheNextAsker() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let model = try model(store: store, defaults: defaults())
        model.coachReadsHealthTrends = true

        await model.loadHealthTrends()
        await model.loadHealthTrends()

        #expect(await store.queries == 3, "the second ask reused the first read's answer")
        #expect(model.healthTrends != .off, "both askers land on the drawn trends")
    }

    @Test("Opted in with history draws the same summary the coach is given")
    func optedInWithHistoryDrawsTheTrends() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let model = try model(store: store, defaults: defaults())

        model.coachReadsHealthTrends = true
        model.requestReadAccess()
        await model.authorizationRequest?.value

        let context = try #require(await model.context())
        #expect(model.healthTrends == .trends(context))
    }

    /// Nothing is drawn before the person has asked for it, and nothing is
    /// asked of Health either — the load is as inert as `context()` is.
    @Test("The trends stay off, and silent, until the opt-in is given")
    func theTrendsStayOffUntilOptedIn() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let model = try model(store: store, defaults: defaults())

        await model.loadHealthTrends()

        #expect(model.healthTrends == .off)
        #expect(await store.queries == 0)
    }

    @Test("The Mindful Minutes write is on until somebody switches it off")
    func mindfulMinutesWriteDefaultsOn() throws {
        let defaults = try defaults()
        let model = model(store: ScriptedHealthStore(), defaults: defaults)

        #expect(model.writesMindfulMinutes)
        #expect(MindfulMinutesRecorder.writesToHealth(in: defaults))
    }

    @Test("Switching the write off survives a relaunch and reaches the recorder")
    func mindfulMinutesWriteOffPersists() throws {
        let defaults = try defaults()
        model(store: ScriptedHealthStore(), defaults: defaults).writesMindfulMinutes = false

        let relaunched = model(store: ScriptedHealthStore(), defaults: defaults)

        #expect(!relaunched.writesMindfulMinutes)
        #expect(
            !MindfulMinutesRecorder.writesToHealth(in: defaults),
            "the recorder reads the same stored choice the switch wrote"
        )
    }

    @Test("Erasing returns the write to its default of on")
    func eraseRestoresTheWrite() async throws {
        let defaults = try defaults()
        let model = model(store: ScriptedHealthStore(), defaults: defaults)
        model.writesMindfulMinutes = false

        await model.erase()

        #expect(model.writesMindfulMinutes)
        #expect(
            defaults.object(forKey: MindfulMinutesRecorder.preferenceKey) == nil,
            "erased means forgotten, not re-stated"
        )
    }

    /// Withdrawing clears the drawn numbers in the same breath, rather than
    /// leaving them on screen until something else refreshes: they are the one
    /// thing on that screen this app promises not to keep.
    @Test("Withdrawing the opt-in blanks the trends immediately")
    func withdrawingBlanksTheTrends() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let model = try model(store: store, defaults: defaults())

        model.coachReadsHealthTrends = true
        model.requestReadAccess()
        await model.authorizationRequest?.value
        #expect(model.healthTrends != .off)

        model.coachReadsHealthTrends = false

        #expect(model.healthTrends == .off)
    }

    /// The leak this gate exists to close, and the case a check at the coach's
    /// call site would miss: a subscription lapses, the opt-in stays on because
    /// it is the person's preference and nobody took it away, and every request
    /// after that would carry their HRV. Health is not read at all — asserted
    /// through the store's own query count, because a nil context could also be
    /// a read that found nothing.
    @Test("A lapsed subscriber's opt-in reads nothing")
    func aFreeTierReadsNothing() async throws {
        let store = ScriptedHealthStore(
            restingHeartRate: Self.trendingSeries(recent: 62, baseline: 58)
        )
        let defaults = try defaults()
        let model = model(store: store, defaults: defaults, tier: .free)
        model.coachReadsHealthTrends = true

        #expect(await model.context() == nil)
        #expect(await store.queries == 0, "no read may happen below the tier")
        #expect(model.healthTrends == .off)
        #expect(
            model.coachReadsHealthTrends,
            "the preference is theirs and survives the subscription lapsing"
        )
    }
}
