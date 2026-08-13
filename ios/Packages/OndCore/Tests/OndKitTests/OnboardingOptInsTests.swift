import Foundation
@testable import OndKit
import Testing

/// The four switches onboarding collects, and the two promises attached to
/// them: nothing on that screen raises a system prompt, and anything nobody
/// touched is never written at all.
///
/// Its own suite rather than part of `OnboardingFlowTests`, because it is about
/// what the flow *does to the rest of the app* rather than about where the flow
/// goes next — and because proving either promise needs the real
/// `SessionSettings` and `HealthContextModel` over a defaults suite of their
/// own, which the stepping tests have no use for.
@MainActor
@Suite("Onboarding opt-ins")
struct OnboardingOptInsTests {
    /// A server that takes whatever it is given. Nothing here is about the
    /// sync; the profile store is present because the flow needs one.
    private struct AcceptingProfiles: ProfileSyncing {
        func fetch() async throws -> Profile {
            .unanswered
        }

        func update(_ profile: Profile) async throws -> Profile {
            profile
        }
    }

    private static func suiteName(_ name: String) -> String {
        "onboarding-opt-in-tests.\(name)"
    }

    /// A `UserDefaults` nobody else shares, cleared first because suites
    /// persist between runs.
    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: Self.suiteName(name))
        suite?.removePersistentDomain(forName: Self.suiteName(name))
        return suite ?? .standard
    }

    /// A trends store that is paid for, because the gate below the opt-in is
    /// `HealthContextModelTests`' subject rather than this suite's — here the
    /// question is only ever *when* Health is asked, not whether it may be read.
    private func healthContext(
        _ store: SpyHealthStore,
        defaults: UserDefaults
    ) -> HealthContextModel {
        HealthContextModel(store: store, defaults: defaults, entitledTier: { .plus })
    }

    /// A flow over real stores, composed the way the app composes it.
    private func model(
        settings: SessionSettings,
        health: HealthContextModel,
        named name: String
    ) -> OnboardingModel {
        OnboardingModel(
            store: ProfileStore(
                profiles: AcceptingProfiles(),
                defaults: defaults("\(name)-profile")
            ),
            consent: SafetyConsentStore(defaults: defaults("\(name)-consent")),
            settings: settings,
            health: health,
            plus: nil
        )
    }

    /// Walks to the opt-ins, which is the one screen this suite is about.
    private func openTheOptIns(_ model: OnboardingModel) {
        while model.step != .optIns {
            model.advance()
        }
    }

    /// The switches reach the stores that own them, and nothing on the way
    /// there asks the system for anything — which is what the step's own footer
    /// promises.
    @Test("The opt-ins are applied on the way out, with no permission asked")
    func appliesTheOptInsWithoutAsking() async {
        let preferences = defaults("applied-preferences")
        let spy = SpyHealthStore()
        let settings = SessionSettings(defaults: preferences)
        let health = healthContext(spy, defaults: preferences)
        let model = model(settings: settings, health: health, named: "applied")

        openTheOptIns(model)

        #expect(model.optIns.asksHowYouFeel, "the flow starts from what the stores hold")
        #expect(!model.optIns.coachReadsHealthTrends)

        model.optIns.asksHowYouFeel = false
        model.optIns.showsWristPulse = true
        model.optIns.coachReadsHealthTrends = true
        model.optIns.writesMindfulMinutes = false
        model.advance()

        #expect(!settings.asksHowYouFeel)
        #expect(settings.showsWristPulse)
        #expect(health.coachReadsHealthTrends)
        #expect(!health.writesMindfulMinutes)

        await #expect(spy.calls.isEmpty, "no system sheet is raised inside the flow")
    }

    /// The other half of the same promise: somebody who taps straight through
    /// leaves an install carrying no preference keys at all. Each of these
    /// properties writes on assignment, so applying all four unconditionally
    /// would file a decision nobody made.
    @Test("Untouched opt-ins write nothing at all")
    func untouchedOptInsWriteNothing() {
        let name = Self.suiteName("untouched-preferences")
        let preferences = defaults("untouched-preferences")
        let settings = SessionSettings(defaults: preferences)
        let health = healthContext(SpyHealthStore(), defaults: preferences)
        let model = model(settings: settings, health: health, named: "untouched")

        while !model.isFinished {
            model.advance()
        }

        #expect(
            (preferences.persistentDomain(forName: name) ?? [:]).isEmpty,
            "a skipped flow is indistinguishable from an install nobody set up"
        )
    }

    /// The read opt-in given here is a promise redeemed later: Health is asked
    /// at the first read the coach actually makes, once, and not again.
    @Test("The deferred Health ask fires once, at the first read")
    func theDeferredAskFiresOnceAtFirstUse() async {
        let preferences = defaults("deferred-preferences")
        let spy = SpyHealthStore()
        let health = healthContext(spy, defaults: preferences)
        let model = model(
            settings: SessionSettings(defaults: preferences),
            health: health,
            named: "deferred"
        )

        openTheOptIns(model)
        model.optIns.coachReadsHealthTrends = true
        model.advance()

        await #expect(spy.calls.isEmpty)

        _ = await health.context()
        await #expect(spy.calls == [.requestedRead])

        _ = await health.context()
        await #expect(spy.calls == [.requestedRead], "the debt is paid once")

        // And the opt-in survives the launch the flow ran in: somebody may
        // finish onboarding and not ask the coach anything for a week.
        let relaunched = healthContext(SpyHealthStore(), defaults: preferences)
        #expect(relaunched.coachReadsHealthTrends)
    }
}
