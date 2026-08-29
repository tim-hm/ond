import Foundation
import Observation

/// Drives the first-run stepper: which screen is up, what has been answered,
/// what the answers switch on, and when the flow is done with somebody.
/// In `OndKit` rather than the app target, which has no test bundle, so the
/// transitions can be tested on the host.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: Step = .welcome

    /// Whether the flow is done with this person.
    ///
    /// A flag rather than a final step, because there is nothing left to draw:
    /// the cover the flow lives in dismisses on this, and a screen whose only
    /// content was a button to leave was charging a tap for nothing.
    public private(set) var isFinished = false

    /// What to call this person, as typed. Narrowed while typing by the rule
    /// `Profile.clampedToServerLimits()` applies on the way out, so nothing
    /// saves locally that the server then refuses on every launch. Trimming
    /// happens on the way onto the profile, so a space typed between two words
    /// survives.
    public var givenName: String = "" {
        didSet {
            let clamped = givenName.clampedName(toScalars: Profile.maxGivenNameLength)
            if clamped != givenName {
                givenName = clamped
            }
        }
    }

    /// In the order they were picked, which is the order they are shown back.
    public private(set) var goals: [TechniqueGoal] = []
    public var experienceLevel: ExperienceLevel?

    /// Where the reminder dial arrives: `daily`, not `never`. The row states
    /// its own position, so somebody who wants no reminder is one tap from
    /// saying so. It is the one default in this flow that asks iOS for
    /// something, and the notification prompt is raised on the way out of the
    /// screen that shows it.
    public var reminderIntensity: ReminderIntensity = .daily {
        didSet { hasMovedDial = true }
    }

    /// Whether the dial above was moved by a person rather than merely arrived
    /// at its default. Read by [`hasAnswered`], and by nothing else — what is
    /// *stored* is the dial's position either way.
    private var hasMovedDial = false

    /// The switches as they stand on screen. Nothing is written anywhere until
    /// the step is left — see [`applyOptIns()`].
    public var optIns: OptIns

    /// The switches as this flow found them, so only what somebody moved is
    /// written back. A `let`, because the forward exit can run twice — Back to
    /// `you`, then forward — and comparing against the values the flow started
    /// from makes the second pass write the same values.
    let arrived: OptIns

    /// What the server already held for this identity, when the answer arrived
    /// too late to close the flow — see [`restoreIfPossible()`]. Kept as the
    /// base the answers merge over, because `UpdateProfile` replaces every
    /// column: without it, finishing the flow erases what it never asks for.
    private var restoredBase: Profile?

    private let store: ProfileStore
    private let catalogue: TechniqueListModel?
    private let consent: SafetyConsentStore
    /// These three are internal rather than private only because the opt-ins
    /// step's own two methods live in the file beside this one.
    let schedules: ScheduleStore?
    let settings: SessionSettings?
    let health: HealthContextModel?
    private let plus: SubscriptionStore?

    /// - Parameters:
    ///   - consent: required, unlike the optional collaborators: a step that
    ///     records nothing satisfies nothing.
    ///   - plus: no default, because absent this offers önd+ to a subscriber.
    ///   - startingAt: a later screen runs none of its predecessors.
    public init(
        store: ProfileStore,
        schedules: ScheduleStore? = nil,
        catalogue: TechniqueListModel? = nil,
        consent: SafetyConsentStore = SafetyConsentStore(),
        settings: SessionSettings? = nil,
        health: HealthContextModel? = nil,
        plus: SubscriptionStore?,
        startingAt: Step = .welcome
    ) {
        step = startingAt
        self.store = store
        self.schedules = schedules
        self.catalogue = catalogue
        self.consent = consent
        self.settings = settings
        self.health = health
        self.plus = plus

        var optIns = OptIns.freshInstall
        if let settings {
            optIns.asksHowYouFeel = settings.asksHowYouFeel
            optIns.showsWristPulse = settings.showsWristPulse
        }
        if let health {
            optIns.coachReadsHealthTrends = health.coachReadsHealthTrends
            optIns.writesMindfulMinutes = health.writesMindfulMinutes
        }
        self.optIns = optIns
        arrived = optIns
    }

    /// The safety terms this flow puts on screen.
    public var safetyTerms: SafetyConsent {
        consent.terms
    }

    /// Whether this person already holds önd+. Read live from the store rather
    /// than snapshotted: a purchase made on the trial step moves the tier and
    /// nothing else reports it, so the screen watches this and calls
    /// `advance()`.
    public var isEntitled: Bool {
        (plus?.tier ?? .free) >= .plus
    }

    /// The steps this person will see, in the order the progress indicator
    /// draws them. Derived, because a subscriber never sees the offer: listing
    /// a step [`advance()`] hops over leaves a dot unreachable and has
    /// VoiceOver announce a total nobody reaches. A trial already on screen
    /// stays listed until the entitlement observation advances past it.
    public var progressSteps: [Step] {
        Step.allCases.filter { step in
            step != .trial || !isEntitled || self.step == .trial
        }
    }

    /// Whether this person has told the flow anything yet. Asked of the
    /// profile the answers make rather than field by field, so a restore and
    /// the server's copy turn on one question. The dial is put back to
    /// `Profile.unanswered` unless somebody moved it: an untouched default
    /// would report a fresh install as answered and skip the restore.
    public var hasAnswered: Bool {
        var answered = profile
        if !hasMovedDial {
            answered.reminderIntensity = Profile.unanswered.reminderIntensity
        }
        return answered.hasAnswers
    }

    /// Adopts the answers the server already holds, closing the flow if it
    /// finds them. It runs alongside the questions, so no network wait sits
    /// between launch and the welcome screen. Answers arriving late are merged
    /// rather than dropped, because `UpdateProfile` replaces every column.
    /// - Returns: whether the flow should close, having adopted a profile.
    public func restoreIfPossible() async -> Bool {
        guard !hasAnswered else { return false }
        guard let restored = await store.restoredProfile() else { return false }

        // Asked again on the way back: the request was in flight while the
        // person could answer, and an answer given here is both the more recent
        // of the two and the one they are looking at.
        let isTooLate = hasAnswered || store.hasCompletedOnboarding
        restoredBase = restored

        guard isTooLate else {
            store.adopt(restored)
            return true
        }

        // Where the flow finished under the fetch, the save has already gone
        // out with blanks in it. This is the write that repairs it; where the
        // flow is only part-way through, the base above is enough and the
        // ordinary save on the way out of the opt-ins carries it.
        if store.hasCompletedOnboarding {
            await store.save(profile)
        }
        return false
    }

    /// Adds or removes a goal, keeping the order the person picked in.
    public func toggle(_ goal: TechniqueGoal) {
        if let index = goals.firstIndex(of: goal) {
            goals.remove(at: index)
        } else {
            goals.append(goal)
        }
    }

    public func isSelected(_ goal: TechniqueGoal) -> Bool {
        goals.contains(goal)
    }

    /// Whether the current step can be passed by — the four steps a Skip is
    /// drawn on. It does what Next does; the label is the difference. The
    /// safety terms alone remain a wall.
    public var canSkip: Bool {
        Step.skippable.contains(step)
    }

    /// Whether there is a screen behind this one to return to: every screen
    /// after Welcome except the safety wall. Going back from the offer may
    /// revisit stored answers, but applying the same diff again is idempotent.
    /// Back from `you` reaches the welcome, which refuses Back in turn.
    public var canGoBack: Bool {
        step == .you || step == .optIns || step == .trial
    }

    /// Moves on: everything that happens on the way out of a step, then the
    /// step change. The answers are stored on the way out of `optIns`, so
    /// somebody who quits on the trial or the safety screen relaunches into
    /// the safety-only gate `FirstRunGate` draws. The reminder is seeded last,
    /// because it needs the catalogue fetch.
    public func advance() {
        if step == .optIns {
            store.complete(with: profile)
            applyOptIns()
            // Not awaited: the person is a tap or two from breathing, and the
            // upload has a whole app lifetime to succeed in. `ProfileStore` has
            // already written the answers and closed onboarding by this point.
            Task { await store.syncIfNeeded() }
        }

        if step == .safety {
            // Written on the way out of the step rather than when the screen
            // appears, because pressing the button is the agreement — reaching
            // the screen is not.
            consent.record()
            seedReminder()
            isFinished = true
            return
        }

        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next

        // Nobody is sold what they already have. Somebody who reinstalls with a
        // live subscription meets the trial screen with nothing on it they can
        // act on, so they never meet it.
        if step == .trial, isEntitled {
            advance()
        }
    }

    /// Passes a step by. The answers given so far are kept, and the side
    /// effects of leaving a step happen either way. Guarded rather than left
    /// to the view, because the safety wall having no way around it is a rule,
    /// and a rule held up by an undrawn button is one refactor from gone.
    public func skip() {
        guard canSkip else { return }
        advance()
    }

    /// Returns to the screen before, where there is one. Guarded on
    /// [`canGoBack`] for the reason [`skip()`] is guarded: "you cannot go back
    /// past the save" is a rule about what this flow has already stored.
    public func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Makes the reminder the stored dial position implies. The work is
    /// `ReminderDial.seedIfNeeded()`'s, because first run has two exits:
    /// somebody who quit after the answers were stored comes back to the
    /// safety terms with no `OnboardingModel` near them. Not awaited, because
    /// the dial waits on the catalogue fetch.
    private func seedReminder() {
        guard let schedules, let catalogue else { return }
        let dial = ReminderDial(profiles: store, schedules: schedules, catalogue: catalogue)

        Task { await dial.seedIfNeeded() }
    }

    /// The answers as they stand, laid over whatever the profile already
    /// holds. An overlay, not a fresh `Profile`: `UpdateProfile` replaces
    /// every column, so a value built from the four answers here would erase
    /// the display name, gender and birth band the server holds. Those stay
    /// editable in Settings. It is narrowed so the server accepts it.
    public var profile: Profile {
        var merged = restoredBase ?? store.profile
        merged.goals = goals
        merged.experienceLevel = experienceLevel
        merged.reminderIntensity = reminderIntensity
        merged.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.clampedToServerLimits()
    }
}
