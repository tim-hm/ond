import Foundation
@testable import OndKit
import Testing

/// Drives the real stepper and the real store through the `ProfileSyncing`
/// seam. What is under test is the promise that onboarding finishes without a
/// server: the flow is the only screen a first-run user cannot get past.
///
/// The second promise this suite carries is quieter and newer — a person who
/// taps straight through leaves an install indistinguishable from one nobody
/// set up. Onboarding now collects four preferences that used to live only in
/// Settings, and the whole of that promise is that untouched ones are never
/// written.
@MainActor
@Suite("Onboarding")
struct OnboardingFlowTests {
    /// Records what it was asked to send, and can be told to refuse — which is
    /// what a first launch on a train looks like.
    private final class RecordingWriter: ProfileSyncing, @unchecked Sendable {
        private(set) var sent: [Profile] = []
        var isReachable = true

        func fetch() async throws -> Profile {
            guard isReachable else {
                throw ProfileRepositoryError.transport(.stub("offline"))
            }
            return .unanswered
        }

        @discardableResult
        func update(_ profile: Profile) async throws -> Profile {
            guard isReachable else {
                throw ProfileRepositoryError.transport(.stub("offline"))
            }
            sent.append(profile)
            return profile
        }
    }

    /// Walks past the welcome screen, which asks nothing.
    ///
    /// A loop rather than a count of `advance()` calls, so a test about what
    /// happens *after* the questions start does not encode how many screens
    /// precede them. The two tests that are about the stepping itself —
    /// `walksTheSteps` and `skipsWhereDecliningIsAnAnswer` — step explicitly
    /// instead, and are meant to fail when the order changes.
    private func openTheQuestions(_ model: OnboardingModel) {
        while model.step != .you {
            model.advance()
        }
    }

    /// Walks the rest of the flow, taking every screen as it stands.
    private func finish(_ model: OnboardingModel) {
        while !model.isFinished {
            model.advance()
        }
    }

    private static func suiteName(_ name: String) -> String {
        "onboarding-tests.\(name)"
    }

    /// A `UserDefaults` nobody else shares, so a test cannot read another's
    /// answers or the developer's own.
    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: Self.suiteName(name))
        // Suites persist between runs; a stale one would make the first
        // assertion in every test depend on the previous run.
        suite?.removePersistentDomain(forName: Self.suiteName(name))
        return suite ?? .standard
    }

    @Test("The stepper walks the screens in order and back again")
    func walksTheSteps() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("steps"))
        let model = OnboardingModel(store: store, plus: nil)

        #expect(model.step == .welcome)
        #expect(!model.canGoBack, "the welcome is not a place to be part-way through")

        model.advance()
        #expect(model.step == .you)

        model.advance()
        #expect(model.step == .optIns)

        model.back()
        #expect(model.step == .you)

        // Back from the first question reaches the welcome, which is a page to
        // re-read rather than a question to be part-way through, and stops
        // there — the way on is forward.
        model.back()
        #expect(model.step == .welcome)
        #expect(!model.canGoBack)

        model.advance()
        model.advance()
        model.advance()
        #expect(model.step == .trial)
        #expect(!model.canGoBack, "the answers behind the offer are already saved")

        model.advance()
        #expect(model.step == .safety)
        #expect(!model.canGoBack)
        #expect(!model.isFinished, "reaching the terms is not agreeing to them")

        model.advance()
        #expect(model.isFinished)
    }

    /// Skip is drawn where declining is a whole answer, and refused everywhere
    /// else: the welcome has nothing to decline, and the safety terms are a
    /// wall.
    @Test("Skip passes the three optional screens and nothing else")
    func skipsWhereDecliningIsAnAnswer() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("skip"))
        let consent = SafetyConsentStore(defaults: defaults("skip-consent"))
        let model = OnboardingModel(store: store, consent: consent, plus: nil)

        #expect(!model.canSkip, "the welcome screen has nothing to skip")
        model.skip()
        #expect(model.step == .welcome)

        model.advance()
        #expect(model.canSkip)
        model.skip()
        #expect(model.step == .optIns)

        #expect(model.canSkip)
        model.skip()
        #expect(model.step == .trial)

        #expect(model.canSkip, "nobody owes this app a subscription")
        model.skip()
        #expect(model.step == .safety)

        #expect(!model.canSkip, "the safety terms have no way around them")
        model.skip()
        #expect(model.step == .safety)
        #expect(!model.isFinished)
        #expect(consent.needsConsent)

        // Nothing was declared on the way through, and the empty answers are
        // what got stored. The dial is the exception by design: its default is a
        // proposal on a screen somebody passed rather than a blank they left.
        #expect(model.profile.goals.isEmpty)
        #expect(model.profile.experienceLevel == nil)
        #expect(model.profile.givenName.isEmpty)
        #expect(model.profile.reminderIntensity == .daily)
    }

    /// Skipping declines to finish a question, not to have started the flow:
    /// answers already given survive it.
    @Test("Skip keeps the answers given so far")
    func skipKeepsPartialAnswers() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("skip-keep"))
        let model = OnboardingModel(store: store, plus: nil)

        openTheQuestions(model)
        model.toggle(.sleep)
        model.givenName = "Robin"
        model.skip()

        #expect(model.step == .optIns)
        #expect(model.profile.goals == [.sleep])
        #expect(model.profile.givenName == "Robin")
    }

    /// Somebody who downloaded this out of curiosity finishes the flow without
    /// declaring anything, and the empty answers are what is stored and sent —
    /// not defaults standing in for answers nobody gave.
    @Test("Onboarding finishes with nothing answered at all")
    func finishesWithNoAnswerAtAll() async {
        let writer = RecordingWriter()
        let store = ProfileStore(profiles: writer, defaults: defaults("no-answer"))
        let consent = SafetyConsentStore(defaults: defaults("no-answer-consent"))
        let model = OnboardingModel(store: store, consent: consent, plus: nil)

        finish(model)

        #expect(store.hasCompletedOnboarding)
        #expect(store.profile.goals.isEmpty)
        #expect(store.profile.experienceLevel == nil)

        await store.syncIfNeeded()
        #expect(writer.sent.first?.goals.isEmpty == true, "the empty set reaches the server")
    }

    /// The resume property `FirstRunGate` rests on: the answers are stored on
    /// the way out of the opt-ins, so quitting on the offer or the terms costs
    /// somebody the safety screen rather than the whole flow.
    @Test("The answers are saved before the offer, not after it")
    func savesOnTheWayOutOfTheOptIns() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("two-phase"))
        let consent = SafetyConsentStore(defaults: defaults("two-phase-consent"))
        let model = OnboardingModel(store: store, consent: consent, plus: nil)

        openTheQuestions(model)
        model.toggle(.focus)
        model.advance()

        #expect(model.step == .optIns)
        #expect(!store.hasCompletedOnboarding, "the questions are not over yet")

        model.advance()

        #expect(model.step == .trial)
        #expect(store.hasCompletedOnboarding)
        #expect(store.profile.goals == [.focus])
        #expect(consent.needsConsent, "the terms are still outstanding")
    }

    /// The offline promise, and the reason the completion flag is local: the
    /// person is through the flow and into the app, and the answers are waiting
    /// to be sent rather than lost.
    @Test("Onboarding completes with no network, and syncs later")
    func completesOfflineAndSyncsLater() async {
        let writer = RecordingWriter()
        writer.isReachable = false

        let store = ProfileStore(profiles: writer, defaults: defaults("offline"))
        let model = OnboardingModel(store: store, plus: nil)

        model.toggle(.sleep)
        model.experienceLevel = .occasional
        model.reminderIntensity = .gentle
        model.givenName = "Robin"

        store.complete(with: model.profile)

        #expect(store.hasCompletedOnboarding)
        #expect(store.isPendingSync)
        #expect(store.profile.goals == [.sleep])

        await store.syncIfNeeded()
        #expect(store.isPendingSync, "a failed send stays outstanding")
        #expect(writer.sent.isEmpty)

        writer.isReachable = true
        await store.syncIfNeeded()

        #expect(!store.isPendingSync)
        #expect(writer.sent.count == 1)
        #expect(writer.sent.first?.experienceLevel == .occasional)
        #expect(writer.sent.first?.givenName == "Robin")
    }

    /// The safety terms are the one step in this flow nobody may pass by, and
    /// the only one that leaves a record of having been seen. Reaching the
    /// screen is not agreeing to it — the record is written by the button, and
    /// that button is also what ends the flow.
    @Test("The safety step is a wall, and agreeing to it is recorded")
    func recordsSafetyConsent() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("consent"))
        let consent = SafetyConsentStore(defaults: defaults("consent-record"))
        let model = OnboardingModel(store: store, consent: consent, plus: nil)

        openTheQuestions(model)
        model.advance()
        model.advance()
        model.advance()

        #expect(model.step == .safety)
        #expect(consent.needsConsent, "arriving at the screen is not agreeing to it")

        #expect(!model.canGoBack, "the answers behind this screen are already saved")
        model.back()
        #expect(model.step == .safety)

        model.advance()

        #expect(model.isFinished)
        #expect(!consent.needsConsent)
        #expect(consent.agreed?.text == SafetyConsent.current.text)
    }

    /// A second launch must not ask the questions again, and must not re-send
    /// answers the server already has.
    @Test("A completed profile survives a relaunch")
    func survivesRelaunch() async {
        let writer = RecordingWriter()
        let suite = defaults("relaunch")

        let first = ProfileStore(profiles: writer, defaults: suite)
        first.complete(with: Profile(
            goals: [.energy],
            experienceLevel: .new,
            reminderIntensity: .daily,
            intentNote: "mornings",
            givenName: "Robin"
        ))
        await first.syncIfNeeded()

        let second = ProfileStore(profiles: writer, defaults: suite)

        #expect(second.hasCompletedOnboarding)
        #expect(!second.isPendingSync)
        #expect(second.profile.goals == [.energy])
        #expect(second.profile.reminderIntensity == .daily)
        #expect(second.profile.givenName == "Robin")

        await second.syncIfNeeded()
        #expect(writer.sent.count == 1, "nothing outstanding means nothing sent")
    }

    /// Somebody reinstalling with a live subscription meets a trial screen with
    /// nothing on it they can act on, so they never meet it — and the step
    /// indicator must not have promised it either. A fifth dot for a screen
    /// that never arrives leaves the total overstated all the way through.
    @Test("An entitled person never sees the trial or counts it in progress")
    func anEntitledPersonSkipsTheTrial() async {
        let plus = SubscriptionStore(
            front: FakeStoreFront(entitlements: [transaction()]),
            entitlements: ScriptedEntitlements(),
            defaults: scratchDefaults()
        )
        await plus.refresh()

        let model = OnboardingModel(
            store: ProfileStore(profiles: RecordingWriter(), defaults: defaults("entitled")),
            consent: SafetyConsentStore(defaults: defaults("entitled-consent")),
            plus: plus
        )

        #expect(model.isEntitled)
        #expect(model.progressSteps == [.welcome, .you, .optIns, .safety])

        openTheQuestions(model)
        model.advance()
        #expect(model.step == .optIns)

        model.advance()
        #expect(model.step == .safety, "the offer is skipped, not merely emptied")
    }

    /// A flow with no subscription behind it counts every screen, including the offer.
    @Test("Without a subscription progress includes all five screens")
    func theOfferIsCountedForEverybodyElse() {
        let store = ProfileStore(profiles: RecordingWriter(), defaults: defaults("unentitled"))
        let model = OnboardingModel(store: store, plus: nil)

        #expect(!model.isEntitled)
        #expect(model.progressSteps == [.welcome, .you, .optIns, .trial, .safety])
    }
}
