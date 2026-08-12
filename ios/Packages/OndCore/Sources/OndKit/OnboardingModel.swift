import Foundation
import Observation

/// Drives the first-run stepper: which screen is up, what has been answered,
/// what the answers switch on, and when the flow is done with somebody.
///
/// Lives in `OndKit` rather than the app target so the flow is testable on
/// the host — the app target has no test bundle, and a stepper whose transitions
/// nobody can exercise is where a screen someone cannot get past comes from.
@MainActor
@Observable
public final class OnboardingModel {
    /// The screens, in the order they are shown.
    ///
    /// An enum with an ordinal rather than an index into an array of views: the
    /// progress indicator, the back button, and the save all need to know where
    /// they are, and a raw `Int` would let them disagree.
    ///
    /// Five, down from eight, and the cuts are the shape of the flow rather
    /// than a trim: the evidence stance folded into the welcome so the app's
    /// case for itself is made once, the four questions became two screens, and
    /// the closing "that's it" went — a screen whose only content is a button
    /// is a tap charged for nothing.
    public enum Step: Int, CaseIterable, Identifiable, Sendable {
        /// What the app is, and what it will not claim. Says the science-first
        /// thing before asking for anything, because a stance stated after the
        /// questions reads as a disclaimer.
        case welcome

        /// The person: what to call them, what they came for, and how much they
        /// want explained. Nothing here is required — every part of it has a
        /// valid unanswered state, and Next takes them all.
        case you

        /// The four switches and the reminder dial, in front of somebody
        /// rather than behind Settings.
        ///
        /// Front-loaded on purpose, and no system sheet fires here: the screen
        /// collects preferences, and the permission each implies is asked at
        /// the first genuine use of the thing it governs. See
        /// [`OnboardingModel/applyOptIns()`].
        case optIns

        /// The önd+ trial, offered once and passed by with "Not now".
        ///
        /// After the opt-ins rather than before them, so the first thing this
        /// app asks somebody for is not money — and after the save, so a person
        /// who quits on the price has still finished onboarding.
        case trial

        /// The safety terms, and the one thing in this flow nobody may pass by.
        ///
        /// Last, immediately before the first session, because that is where a
        /// warning is worth most — the same argument that used to keep a caution
        /// on the exercise screens, applied once. It appears in no progress
        /// indicator, and `Skip` refuses it.
        case safety

        public var id: Self {
            self
        }

        /// What a step indicator counts, and where a Skip is drawn — the middle
        /// three. The welcome is a greeting and `safety` a condition of use;
        /// neither is a place to be part-way through, and neither has anything
        /// to decline.
        public static let counted: [Step] = [.you, .optIns, .trial]
    }

    public private(set) var step: Step = .welcome

    /// Whether the flow is done with this person.
    ///
    /// A flag rather than a final step, because there is nothing left to draw:
    /// the cover the flow lives in dismisses on this, and a screen whose only
    /// content was a button to leave was charging a tap for nothing.
    public private(set) var isFinished = false

    /// What to call this person, as typed. Clamped as it is typed — the same
    /// rule the leaderboard name follows, in the unit `String.clamped(toScalars:)`
    /// explains — so the field stops accepting input rather than letting
    /// somebody write past the point where saving would fail.
    ///
    /// Trimmed on the way onto the profile rather than here, so a space typed
    /// between two words survives being typed.
    public var givenName: String = "" {
        didSet {
            let clamped = givenName.clamped(toScalars: Profile.maxGivenNameLength)
            if clamped != givenName {
                givenName = clamped
            }
        }
    }

    /// In the order they were picked, which is the order they are shown back.
    public private(set) var goals: [TechniqueGoal] = []
    public var experienceLevel: ExperienceLevel?
    public var reminderIntensity: ReminderIntensity = .never

    /// The switches as they stand on screen. Nothing is written anywhere until
    /// the step is left — see [`applyOptIns()`].
    public var optIns: OptIns

    /// The switches as this flow found them, kept so that only what somebody
    /// actually moved is ever written back.
    ///
    /// A `let`, because the step that collects them is left exactly once: Back
    /// reaches `you` and nothing reaches `optIns` a second time.
    let arrived: OptIns

    private let store: ProfileStore
    private let schedules: ScheduleStore?
    private let catalogue: TechniqueListModel?
    private let consent: SafetyConsentStore
    let settings: SessionSettings?
    let health: HealthContextModel?
    private let isEntitled: @MainActor () -> Bool

    /// - Parameters:
    ///   - schedules: where a reminder the person asked for lands. Absent, the
    ///     dial is still stored on the profile and simply rings nothing.
    ///   - catalogue: what that reminder opens with. Also absent-able, and for
    ///     the same reason: onboarding has to finish with no network, and the
    ///     catalogue is a fetch.
    ///   - consent: where agreement to the safety terms is recorded. The one
    ///     collaborator here with no optional form and no do-nothing default: a
    ///     consent step that records nothing satisfies nothing, and an app
    ///     composing this without one would look identical until somebody asked
    ///     what a person had agreed to.
    ///   - settings: where two of the four switches live. Absent, the screen
    ///     still draws them and leaving it writes nothing.
    ///   - health: where the other two live, and the one collaborator that
    ///     needs telling *how* it was asked — see [`applyOptIns`].
    ///   - isEntitled: whether this person already holds önd+, which is the
    ///     whole of the trial step's reason to exist. Defaulted to false, so a
    ///     composition that forgot it offers a trial rather than skipping one
    ///     somebody has not taken.
    public init(
        store: ProfileStore,
        schedules: ScheduleStore? = nil,
        catalogue: TechniqueListModel? = nil,
        consent: SafetyConsentStore = SafetyConsentStore(),
        settings: SessionSettings? = nil,
        health: HealthContextModel? = nil,
        isEntitled: @escaping @MainActor () -> Bool = { false }
    ) {
        self.store = store
        self.schedules = schedules
        self.catalogue = catalogue
        self.consent = consent
        self.settings = settings
        self.health = health
        self.isEntitled = isEntitled

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

    /// Whether this person has told the flow anything yet.
    ///
    /// Asked of the profile the answers make rather than field by field, so the
    /// question a restore turns on and the question asked of the server's copy
    /// are the same one — and a fourth question cannot make them disagree.
    public var hasAnswered: Bool {
        profile.hasAnswers
    }

    /// Adopts the answers the server already holds for this identity, closing
    /// the flow if it finds them.
    ///
    /// Runs *alongside* the questions rather than in front of them. The
    /// alternative — racing the fetch against a short timeout before drawing
    /// anything — puts a network wait between launch and the welcome screen for
    /// every genuinely new user, which is nearly all of them and none of whom
    /// have a profile to restore. Here the flow is on screen immediately, and
    /// somebody with no signal never learns this was attempted.
    ///
    /// - Returns: whether the flow should close, having adopted a profile.
    public func restoreIfPossible() async -> Bool {
        guard !hasAnswered else { return false }
        guard let restored = await store.restoredProfile() else { return false }

        // Asked again on the way back: the request was in flight while the
        // person could answer, and an answer given here is both the more recent
        // of the two and the one they are looking at.
        guard !hasAnswered else { return false }

        store.adopt(restored)
        return true
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

    /// Whether the current step can be passed by without engaging with it — the
    /// three steps a Skip is drawn on.
    ///
    /// It does the same thing Next does, and the label is the difference: on
    /// these three, declining is a whole answer and the word should say so.
    /// The welcome has nothing to decline, and the safety terms are a wall.
    public var canSkip: Bool {
        Step.counted.contains(step)
    }

    /// Whether there is a screen behind this one to return to.
    ///
    /// The two questions, and only those. `trial` and `safety` both sit after
    /// the save, where going back would offer to change something already
    /// stored and sent — and where a second pass over `optIns` would apply its
    /// one-shot switches again.
    ///
    /// Back from `you` reaches the welcome, which is fine: it is a page to
    /// re-read rather than a place to be part-way through, and it refuses Back
    /// in turn.
    public var canGoBack: Bool {
        step == .you || step == .optIns
    }

    /// Moves on: everything that happens on the way out of a step, and then the
    /// step change itself.
    ///
    /// Two phases rather than one save at the end, and the split is
    /// load-bearing. The answers are stored on the way out of `optIns`, so a
    /// person who quits the app on the trial or the safety screen relaunches
    /// into the safety-only gate rather than into the whole flow again —
    /// `FirstRunGate` reads exactly the two records these two phases write.
    ///
    /// The reminder is seeded in the second phase, at the end, because
    /// `ScheduleStore.add` is the one call in this app that asks for
    /// notification permission: at finish that sheet lands over Home, where
    /// somebody has just agreed to start, rather than over a screen selling
    /// them a subscription.
    ///
    /// Nothing is required of any step, so there is no state this refuses in —
    /// the one screen that cannot be passed by refuses `skip` rather than
    /// holding this back, because its button is an agreement and pressing it
    /// has to move.
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
        if step == .trial, isEntitled() {
            advance()
        }
    }

    /// Passes a step by without engaging with it. The answers given so far are
    /// kept — skipping is declining to finish, not undoing — and the side
    /// effects of leaving a step happen either way, because leaving it is what
    /// they are attached to.
    ///
    /// Guarded rather than left to the view: the safety wall having no way
    /// around it is a rule, and a rule enforced only by a button not being
    /// drawn is a rule one refactor from being gone.
    public func skip() {
        guard canSkip else { return }
        advance()
    }

    public func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Makes the reminder the dial asked for, once.
    ///
    /// `never` falls out through `ReminderSeed.schedule` returning nil, so
    /// nothing is created and `ScheduleStore.add` — the one place notification
    /// permission is ever requested — is not reached at all.
    ///
    /// Only ever seeds into an empty list: somebody who already keeps schedules
    /// has an arrangement of their own, and a flow that has just asked one
    /// question about reminders is not entitled to add to it.
    ///
    /// Waits for the catalogue rather than reading whatever it holds at this
    /// instant, because a reminder can only name a technique the app has heard
    /// of and this runs on a first launch — the one launch where the fetch may
    /// still be in the air. Joining the shared load rather than starting a fetch
    /// of its own, and not awaited, so the person is still one tap from
    /// breathing.
    private func seedReminder() {
        guard let schedules, schedules.schedules.isEmpty, let catalogue else { return }
        let goals = goals
        let intensity = reminderIntensity

        Task {
            guard let technique = await catalogue.reminderTechnique(forFirstOf: goals),
                  let seeded = ReminderSeed.schedule(for: intensity, technique: technique),
                  // Re-checked after the await, not only before it: a dial
                  // moved in Settings while the first catalogue fetch was in
                  // the air lands its own schedule through `applyDial`, and a
                  // seed that only looked before waiting would add a second.
                  schedules.schedules.isEmpty
            else {
                return
            }

            schedules.add(seeded)
        }
    }

    /// The answers as they stand.
    ///
    /// Three of `Profile`'s fields are absent on purpose, because this flow no
    /// longer asks for them: the display name is the leaderboard screen's, and
    /// the birth band, gender and intent note are Settings' — every one of them
    /// still editable there, and none of them worth a screen between somebody
    /// and their first breath.
    public var profile: Profile {
        Profile(
            goals: goals,
            experienceLevel: experienceLevel,
            reminderIntensity: reminderIntensity,
            intentNote: "",
            givenName: givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
