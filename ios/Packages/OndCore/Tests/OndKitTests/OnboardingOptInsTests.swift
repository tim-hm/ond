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

    /// Leaving the step asks Health for what the switches say, and the ask is
    /// attached to the switch rather than to some later use of it.
    @Test("The Health asks are the switches that were left on")
    func theHealthAsksFollowTheSwitches() async {
        let preferences = defaults("grants-preferences")
        let spy = SpyHealthStore()
        let health = healthContext(spy, defaults: preferences)
        let model = model(
            settings: SessionSettings(defaults: preferences),
            health: health,
            named: "grants"
        )

        openTheOptIns(model)
        model.optIns.coachReadsHealthTrends = true
        model.advance()
        await model.requestOptInGrants()

        // Mindful Minutes is on by default, so both grants are owed — writes
        // first, which is the one a straight-through install meets alone.
        await #expect(spy.calls == [.requestedMindfulWrite, .requestedRead])

        // And the opt-in survives the launch the flow ran in.
        let relaunched = healthContext(SpyHealthStore(), defaults: preferences)
        #expect(relaunched.coachReadsHealthTrends)
    }

    /// The other half of the same rule: a switch left off asks for nothing, so
    /// declining a feature never costs somebody a system sheet.
    @Test("A switch left off is never asked about")
    func switchesLeftOffAskForNothing() async {
        let preferences = defaults("declined-preferences")
        let spy = SpyHealthStore()
        let health = healthContext(spy, defaults: preferences)
        let model = model(
            settings: SessionSettings(defaults: preferences),
            health: health,
            named: "declined"
        )

        openTheOptIns(model)
        model.optIns.writesMindfulMinutes = false
        model.advance()
        await model.requestOptInGrants()

        await #expect(spy.calls.isEmpty)
    }
}
